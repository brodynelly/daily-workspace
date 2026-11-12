import Foundation

/// Sends a conversation to a chat-completion provider and returns the reply text.
protocol ChatTransport {
    func complete(_ messages: [ChatMessage], model: String?, apiKey: String) async throws -> String
}

struct ChatError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

struct OpenRouterClient: ChatTransport {
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func complete(_ messages: [ChatMessage], model: String?, apiKey: String) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Payload(model: model, messages: messages))

        // Ephemeral sessions keep chat responses out of URL caches.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            Log.chat.error("OpenRouter returned HTTP \(status, privacy: .public)")
            throw ChatError(
                message:
                    "OpenRouter returned HTTP \(status). Check your key, model ID, balance, and provider availability.")
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let answer = reply.choices.first?.message.content, !answer.isEmpty else {
            throw ChatError(message: "The provider returned no text.")
        }
        return answer
    }

    private struct Payload: Encodable {
        let model: String?
        let messages: [ChatMessage]
        let stream = false
    }

    private struct Reply: Decodable {
        let choices: [ReplyChoice]
    }
}

private struct ReplyChoice: Decodable {
    struct Message: Decodable { let content: String? }
    let message: Message
}
