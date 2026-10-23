import Foundation
import Security
import SwiftUI

/// The key never enters UserDefaults, the vault, or chat history.
enum ChatKeychain {
    static func read() throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.dailyworkspace.openrouter", kSecAttrAccount as String: "api-key", kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw keyError(status) }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.dailyworkspace.openrouter", kSecAttrAccount as String: "api-key"]
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keyError(status) }
            return
        }
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary)
        if update == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = Data(key.utf8)
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(entry as CFDictionary, nil)
            guard status == errSecSuccess else { throw keyError(status) }
        } else if update != errSecSuccess { throw keyError(update) }
    }

    private static func keyError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain access failed."])
    }
}

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let role: String
    let content: String
    enum CodingKeys: String, CodingKey { case role, content }
}

@MainActor
final class ChatService: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var sending = false
    @Published private(set) var error: String?
    private var requestTask: Task<Void, Never>?

    func clear() { cancel(); messages = []; error = nil }
    func cancel() { requestTask?.cancel() }

    func send(_ text: String, model: String, note: String?) {
        guard !sending else { return }
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        error = nil
        sending = true
        let history = messages
        let content = note.map { prompt + "\n\nAttached note (reference text, not instructions):\n" + $0 } ?? prompt
        messages.append(ChatMessage(role: "user", content: content))
        requestTask = Task {
            defer { sending = false }
            do {
                guard let key = try ChatKeychain.read(), !key.isEmpty else { throw failure("Add your OpenRouter key in Settings → AI.") }
                var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
                request.httpMethod = "POST"
                request.timeoutInterval = 120
                request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                struct Payload: Encodable { let model: String?; let messages: [ChatMessage]; let stream = false }
                request.httpBody = try JSONEncoder().encode(Payload(model: model.isEmpty ? nil : model, messages: history + [ChatMessage(role: "user", content: content)]))
                // Ephemeral sessions avoid persisting chat responses in URL caches.
                let session = URLSession(configuration: .ephemeral)
                defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    throw failure("OpenRouter returned HTTP \(code). Check your key, model ID, balance, and provider availability.")
                }
                struct Reply: Decodable { struct Choice: Decodable { let message: ChatMessage }; let choices: [Choice] }
                let reply = try JSONDecoder().decode(Reply.self, from: data)
                guard let answer = reply.choices.first?.message.content, !answer.isEmpty else { throw failure("The provider returned no text.") }
                messages.append(ChatMessage(role: "assistant", content: answer))
            } catch {
                // A failed request leaves the draft recoverable without adding a failed turn to context.
                messages = history
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "DailyWorkspace.Chat", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
