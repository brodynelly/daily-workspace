import Foundation

/// Sends one Messages API request and streams the response, including tool calls, thinking blocks and stop reasons.
protocol AgentTransport: Sendable {
    /// Send `request`, reporting progress through `onUpdate` (awaited, in order), and return the full response.
    func send(
        _ request: AgentRequest, apiKey: String, onUpdate: @escaping @Sendable (AgentStreamUpdate) async -> Void
    ) async throws -> AgentResponse
}

/// How much the model thinks before answering (`output_config.effort`).
enum AgentEffort: String, Sendable {
    case low, medium, high, xhigh, max
}

/// One message of the conversation. Content blocks are raw JSON, replayed exactly as stored.
struct AgentMessage: Equatable, Sendable {
    enum Role: String, Sendable {
        case user, assistant
    }

    let role: Role
    let content: [Data]

    var json: OrderedJSON {
        .object([("role", .string(role.rawValue)), ("content", .array(content.map { .raw($0) }))])
    }
}

/// A Messages API request. `body` renders it deterministically, so equal requests are equal bytes.
struct AgentRequest: Sendable {
    var model: String
    var maxTokens: Int
    var effort: AgentEffort
    /// System blocks, stable rules first; the caller puts `cache_control` on the last stable one.
    var system: [OrderedJSON]
    /// Tool definitions in a fixed order.
    var tools: [OrderedJSON]
    var messages: [AgentMessage]
    /// A JSON schema for structured output (`output_config.format`), or nil for free text.
    var outputSchema: OrderedJSON?

    /// The JSON body. Thinking is adaptive (Claude Opus 5.5 cannot turn it off; effort is the control).
    /// Sampling parameters and forced `tool_choice` are never sent: this model rejects them.
    func body(stream: Bool = true) -> Data {
        var outputConfig: [(String, OrderedJSON)] = [("effort", .string(effort.rawValue))]
        if let outputSchema {
            outputConfig.append(("format", .object([("type", .string("json_schema")), ("schema", outputSchema)])))
        }
        var members: [(String, OrderedJSON)] = [
            ("model", .string(model)),
            ("max_tokens", .int(maxTokens)),
            ("stream", .bool(stream)),
            ("thinking", .object([("type", .string("adaptive"))])),
            ("output_config", .object(outputConfig)),
            ("fallbacks", .string("default")),
            // Automatic caching for the growing conversation tail; the stable prefix has its own marker.
            ("cache_control", OrderedJSON.ephemeralCache),
        ]
        if !tools.isEmpty {
            members.append(("tool_choice", .object([("type", .string("auto"))])))
            members.append(("tools", .array(tools)))
        }
        if !system.isEmpty { members.append(("system", .array(system))) }
        members.append(("messages", .array(messages.map(\.json))))
        return OrderedJSON.object(members).encoded()
    }
}

/// A failure the user can act on. Messages never include server response bodies, which can echo note text.
struct AgentError: LocalizedError, Equatable {
    enum Kind: Hashable, Sendable {
        case missingKey, keychain, unauthorized, forbidden, notFound, rateLimited, overloaded, server
        case badRequest, tooLarge, timedOut, offline, network, incomplete, refused, truncated, toolLimit
        case invalidDraft, busy, disabled
    }

    let kind: Kind
    let message: String
    /// Seconds the server asked to wait (`retry-after-ms` or `retry-after`), when it said.
    var retryAfter: TimeInterval?
    /// The server's own retry advice (`x-should-retry`), when it gave one. It overrides the kind's default.
    var shouldRetry: Bool?

    init(_ kind: Kind, _ message: String, retryAfter: TimeInterval? = nil, shouldRetry: Bool? = nil) {
        self.kind = kind
        self.message = message
        self.retryAfter = retryAfter
        self.shouldRetry = shouldRetry
    }

    var errorDescription: String? { message }

    /// Retry hints are transport metadata; two errors are the same when the user would see the same thing.
    static func == (lhs: AgentError, rhs: AgentError) -> Bool {
        lhs.kind == rhs.kind && lhs.message == rhs.message
    }

    static func http(
        status: Int, errorType: String?, retryAfter: String?, provider: String = "Anthropic",
        retryAfterMilliseconds: String? = nil, shouldRetry: String? = nil
    ) -> AgentError {
        var error = httpError(status: status, errorType: errorType, retryAfter: retryAfter, provider: provider)
        error.retryAfter = Self.delay(retryAfterMilliseconds: retryAfterMilliseconds, retryAfter: retryAfter)
        switch shouldRetry?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true": error.shouldRetry = true
        case "false": error.shouldRetry = false
        default: break
        }
        return error
    }

    /// A server-requested wait in seconds: `retry-after-ms` first, then a whole-seconds `retry-after`.
    /// HTTP-date forms are ignored (the policy's own backoff applies).
    static func delay(retryAfterMilliseconds: String?, retryAfter: String?) -> TimeInterval? {
        if let text = retryAfterMilliseconds?.trimmingCharacters(in: .whitespaces), let value = Double(text),
            value.isFinite, value >= 0
        {
            return value / 1000
        }
        if let text = retryAfter?.trimmingCharacters(in: .whitespaces), let value = Double(text), value.isFinite,
            value >= 0
        {
            return value
        }
        return nil
    }

    private static func httpError(
        status: Int, errorType: String?, retryAfter: String?, provider: String
    ) -> AgentError {
        switch status {
        case 400: return AgentError(.badRequest, "\(provider) rejected the request as invalid (HTTP 400).")
        case 401: return AgentError(.unauthorized, "\(provider) rejected the API key. Check it in Settings → AI.")
        case 403:
            return AgentError(
                .forbidden, "This API key isn't allowed to use the model. Check your \(provider) account.")
        case 404:
            return AgentError(.notFound, "\(provider) didn't recognize the model. Check the model in Settings → AI.")
        case 413: return AgentError(.tooLarge, "The conversation is too large to send. Clear it and try again.")
        case 429:
            let wait =
                retryAfter.flatMap(Int.init).map { " Try again in \($0) seconds." } ?? " Wait a moment and try again."
            return AgentError(.rateLimited, "\(provider)'s rate limit was reached." + wait)
        case 529: return overloaded(provider: provider)
        case 500..<600:
            if errorType == "overloaded_error" { return overloaded(provider: provider) }
            return AgentError(.server, "\(provider) had a server problem (HTTP \(status)). Try again in a moment.")
        default: return AgentError(.server, "\(provider) returned HTTP \(status).")
        }
    }

    /// An `error` event in the middle of a stream. Only its `type` is read.
    static func stream(_ error: [String: Any]?, provider: String = "Anthropic") -> AgentError {
        switch error?["type"] as? String {
        case "overloaded_error": return overloaded(provider: provider)
        case "rate_limit_error": return http(status: 429, errorType: nil, retryAfter: nil, provider: provider)
        case "authentication_error": return http(status: 401, errorType: nil, retryAfter: nil, provider: provider)
        case "permission_error": return http(status: 403, errorType: nil, retryAfter: nil, provider: provider)
        case "invalid_request_error": return http(status: 400, errorType: nil, retryAfter: nil, provider: provider)
        case "request_too_large": return http(status: 413, errorType: nil, retryAfter: nil, provider: provider)
        default: return AgentError(.server, "\(provider) stopped the response with an error. Try again in a moment.")
        }
    }

    static func network(_ error: URLError, provider: String = "Anthropic") -> AgentError {
        switch error.code {
        case .timedOut: return AgentError(.timedOut, "\(provider) stopped responding for too long. Try again.")
        case .networkConnectionLost:
            // A dropped connection is transient (and retried); being offline is not.
            return AgentError(.network, "The connection to \(provider) dropped. Try again.")
        case .notConnectedToInternet, .dataNotAllowed:
            return AgentError(.offline, "The Mac is offline. Connect to the internet and try again.")
        default: return AgentError(.network, "Couldn't reach \(provider). Check your connection and try again.")
        }
    }

    private static func overloaded(provider: String) -> AgentError {
        AgentError(.overloaded, "\(provider) is overloaded right now. Try again in a moment.")
    }
}
