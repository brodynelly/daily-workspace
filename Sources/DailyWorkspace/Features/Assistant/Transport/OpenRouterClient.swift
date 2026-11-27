import Foundation

/// OpenRouter's Messages-format API. Model IDs are passed through unchanged; no Claude-specific controls are sent.
struct OpenRouterClient: AgentTransport {
    static let defaultEndpoint = URL(string: "https://openrouter.ai/api/v1/messages")!

    var endpoint = defaultEndpoint
    /// Longest wait for the next bytes. Adaptive thinking can pause output for minutes (Claude Code never goes
    /// below 5 minutes), so a shorter idle limit would cut off healthy answers.
    var idleTimeout: TimeInterval = 300
    var totalTimeout: TimeInterval = 600
    /// Test hook: `URLProtocol` classes to put in front of the network.
    var protocolClasses: [AnyClass]?

    func urlRequest(for request: AgentRequest, apiKey: String) -> URLRequest {
        var urlRequest = URLRequest(
            url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: idleTimeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "accept")
        urlRequest.httpBody = request.openRouterBody()
        return urlRequest
    }

    func send(
        _ request: AgentRequest, apiKey: String, onUpdate: @escaping @Sendable (AgentStreamUpdate) async -> Void
    ) async throws -> AgentResponse {
        try await MessagesAPIClient(
            provider: "OpenRouter", idleTimeout: idleTimeout, totalTimeout: totalTimeout,
            protocolClasses: protocolClasses
        ).send(urlRequest(for: request, apiKey: apiKey), onUpdate: onUpdate)
    }
}

extension AgentRequest {
    /// Provider-neutral Messages payload: tool results are retained, while Claude-only thinking and cache
    /// directives are omitted. A draft's output schema is not sent: OpenRouter documents
    /// `output_config.format` as Claude-specific, so the draft prompt asks for JSON and the caller validates it.
    func openRouterBody() -> Data {
        var members: [(String, OrderedJSON)] = [
            ("model", .string(model)),
            ("max_tokens", .int(maxTokens)),
            ("stream", .bool(true)),
        ]
        if !tools.isEmpty {
            members.append(("tools", .array(tools.map { $0.removingClaudeDirectives(removeStrict: true) })))
        }
        if !system.isEmpty {
            members.append(("system", .array(system.map { $0.removingClaudeDirectives() })))
        }
        let renderedMessages = messages.map { message in
            let blocks = message.content.compactMap { block -> OrderedJSON? in
                guard let object = parseJSONObject(block), let type = object["type"] as? String else {
                    return .raw(block)
                }
                if message.role == .assistant, ["thinking", "redacted_thinking", "fallback"].contains(type) {
                    return nil
                }
                return OrderedJSON(foundation: object).removingClaudeDirectives()
            }
            return OrderedJSON.object([("role", .string(message.role.rawValue)), ("content", .array(blocks))])
        }
        members.append(("messages", .array(renderedMessages)))
        return OrderedJSON.object(members).encoded()
    }
}

extension OrderedJSON {
    fileprivate func removingClaudeDirectives(removeStrict: Bool = false) -> OrderedJSON {
        let value: OrderedJSON
        if case .raw(let data) = self, let object = parseJSONObject(data) {
            value = OrderedJSON(foundation: object)
        } else {
            value = self
        }
        guard case .object(let members) = value else { return value }
        return .object(members.filter { key, _ in key != "cache_control" && (!removeStrict || key != "strict") })
    }
}
