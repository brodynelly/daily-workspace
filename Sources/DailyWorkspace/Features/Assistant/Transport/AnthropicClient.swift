import Foundation

/// The Anthropic Messages API over HTTPS, streamed as server-sent events.
struct AnthropicClient: AgentTransport {
    static let defaultEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    /// Server-side refusal fallbacks in the `fallbacks: "default"` form.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    var endpoint = defaultEndpoint
    /// Longest wait for the next bytes. Adaptive thinking can pause output for minutes (Claude Code never goes
    /// below 5 minutes), so a shorter idle limit would cut off healthy answers.
    var idleTimeout: TimeInterval = 300
    /// Longest a whole streamed response may take.
    var totalTimeout: TimeInterval = 600
    /// Test hook: `URLProtocol` classes to put in front of the network.
    var protocolClasses: [AnyClass]?

    func urlRequest(for request: AgentRequest, apiKey: String) -> URLRequest {
        var urlRequest = URLRequest(
            url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: idleTimeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "accept")
        urlRequest.httpBody = request.body(stream: true)
        return urlRequest
    }

    func send(
        _ request: AgentRequest, apiKey: String, onUpdate: @escaping @Sendable (AgentStreamUpdate) async -> Void
    ) async throws -> AgentResponse {
        try await MessagesAPIClient(
            provider: "Anthropic", idleTimeout: idleTimeout, totalTimeout: totalTimeout,
            protocolClasses: protocolClasses
        ).send(urlRequest(for: request, apiKey: apiKey), onUpdate: onUpdate)
    }
}
