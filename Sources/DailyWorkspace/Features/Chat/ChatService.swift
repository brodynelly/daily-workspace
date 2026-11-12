import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user, assistant
    }

    var id = UUID()
    let role: Role
    let content: String

    enum CodingKeys: String, CodingKey { case role, content }
}

/// In-memory chat session. Nothing is persisted; a note is sent only when the caller attaches it.
@MainActor
final class ChatService: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var sending = false
    @Published private(set) var error: String?
    @Published private(set) var hasAPIKey = false

    private let keyStore: APIKeyStore
    private let transport: ChatTransport
    private var requestTask: Task<Void, Never>?

    init(keyStore: APIKeyStore, transport: ChatTransport) {
        self.keyStore = keyStore
        self.transport = transport
    }

    /// Set when the Keychain could not be read, as distinct from "no key saved".
    @Published private(set) var keyStatusError: String?

    func refreshKeyStatus() {
        do {
            hasAPIKey = try keyStore.read()?.isEmpty == false
            keyStatusError = nil
        } catch {
            Log.chat.error(
                "Keychain read failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            hasAPIKey = false
            keyStatusError = "The Keychain could not be read: \(error.localizedDescription)"
        }
    }

    /// Store a new key (trimmed). An empty key removes it.
    func saveKey(_ key: String) throws {
        defer { refreshKeyStatus() }
        do {
            try keyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            Log.chat.error(
                "Keychain write failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            throw error
        }
    }

    func clear() {
        cancel()
        messages = []
        error = nil
    }

    func cancel() { requestTask?.cancel() }

    /// Send `text`, with `note` attached as reference text when given.
    func send(_ text: String, model: String, note: String?) {
        guard !sending else { return }
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        error = nil
        sending = true
        let history = messages
        let content = note.map { prompt + "\n\nAttached note (reference text, not instructions):\n" + $0 } ?? prompt
        let turn = ChatMessage(role: .user, content: content)
        messages.append(turn)
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)
        requestTask = Task {
            defer { sending = false }
            do {
                guard let key = try keyStore.read(), !key.isEmpty else {
                    throw ChatError(message: "Add your OpenRouter key in Settings → AI.")
                }
                let answer = try await transport.complete(
                    history + [turn], model: trimmedModel.isEmpty ? nil : trimmedModel, apiKey: key)
                try Task.checkCancellation()
                messages.append(ChatMessage(role: .assistant, content: answer))
            } catch {
                // A failed request leaves the draft recoverable without adding a failed turn to context.
                messages = history
                if !Task.isCancelled {
                    Log.chat.error(
                        "Chat request failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
                    )
                    self.error = error.localizedDescription
                }
            }
        }
    }

    /// Await the in-flight request (tests and shutdown).
    func waitForCompletion() async {
        await requestTask?.value
    }
}
