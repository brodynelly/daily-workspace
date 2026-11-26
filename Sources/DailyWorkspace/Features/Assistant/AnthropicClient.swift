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

    var json: JSONValue {
        .object([("role", .string(role.rawValue)), ("content", .array(content.map { .raw($0) }))])
    }
}

/// A Messages API request. `body` renders it deterministically, so equal requests are equal bytes.
struct AgentRequest: Sendable {
    var model: String
    var maxTokens: Int
    var effort: AgentEffort
    /// System blocks, stable rules first; the caller puts `cache_control` on the last stable one.
    var system: [JSONValue]
    /// Tool definitions in a fixed order.
    var tools: [JSONValue]
    var messages: [AgentMessage]
    /// A JSON schema for structured output (`output_config.format`), or nil for free text.
    var outputSchema: JSONValue?

    /// The JSON body. Thinking is adaptive (Claude Opus 5.5 cannot turn it off; effort is the control).
    /// Sampling parameters and forced `tool_choice` are never sent: this model rejects them.
    func body(stream: Bool = true) -> Data {
        var outputConfig: [(String, JSONValue)] = [("effort", .string(effort.rawValue))]
        if let outputSchema {
            outputConfig.append(("format", .object([("type", .string("json_schema")), ("schema", outputSchema)])))
        }
        var members: [(String, JSONValue)] = [
            ("model", .string(model)),
            ("max_tokens", .int(maxTokens)),
            ("stream", .bool(stream)),
            ("thinking", .object([("type", .string("adaptive"))])),
            ("output_config", .object(outputConfig)),
            ("fallbacks", .string("default")),
            // Automatic caching for the growing conversation tail; the stable prefix has its own marker.
            ("cache_control", JSONValue.ephemeralCache),
        ]
        if !tools.isEmpty {
            members.append(("tool_choice", .object([("type", .string("auto"))])))
            members.append(("tools", .array(tools)))
        }
        if !system.isEmpty { members.append(("system", .array(system))) }
        members.append(("messages", .array(messages.map(\.json))))
        return JSONValue.object(members).encoded()
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
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return AgentError(.offline, "The Mac is offline. Connect to the internet and try again.")
        default: return AgentError(.network, "Couldn't reach \(provider). Check your connection and try again.")
        }
    }

    private static func overloaded(provider: String) -> AgentError {
        AgentError(.overloaded, "\(provider) is overloaded right now. Try again in a moment.")
    }
}

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

/// The shared Messages SSE network path. Provider-specific request bodies and authentication stay with each client.
struct MessagesAPIClient {
    let provider: String
    let idleTimeout: TimeInterval
    let totalTimeout: TimeInterval
    let protocolClasses: [AnyClass]?

    func send(
        _ request: URLRequest, onUpdate: @escaping @Sendable (AgentStreamUpdate) async -> Void
    ) async throws -> AgentResponse {
        try Task.checkCancellation()
        // Ephemeral: no URL cache, cookies or credentials persist for this traffic.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.timeoutIntervalForResource = totalTimeout
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        let session = URLSession(configuration: configuration, delegate: MessagesNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let errorType = await Self.errorType(in: bytes)
                Log.assistant.error(
                    "\(provider, privacy: .public): HTTP \(status, privacy: .public), \(errorType ?? "-", privacy: .public)"
                )
                throw AgentError.http(
                    status: status, errorType: errorType, retryAfter: http?.value(forHTTPHeaderField: "retry-after"),
                    provider: provider, retryAfterMilliseconds: http?.value(forHTTPHeaderField: "retry-after-ms"),
                    shouldRetry: http?.value(forHTTPHeaderField: "x-should-retry"))
            }
            var parser = SSEParser()
            var accumulator = MessageStreamAccumulator()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard let event = parser.push(byte) else { continue }
                if let update = try apply(event, to: &accumulator) { await onUpdate(update) }
            }
            if let event = parser.finish(), let update = try apply(event, to: &accumulator) { await onUpdate(update) }
            try Task.checkCancellation()
            guard accumulator.isComplete else {
                throw AgentError(.incomplete, "The response ended before it finished. Try again.")
            }
            return accumulator.finalResponse()
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            Log.assistant.error("\(provider, privacy: .public) request failed: \(Log.code(error), privacy: .public)")
            throw AgentError.network(error, provider: provider)
        }
    }

    private func apply(_ event: SSEEvent, to accumulator: inout MessageStreamAccumulator) throws -> AgentStreamUpdate? {
        if provider != "Anthropic",
            let object = parseJSONObject(Data(event.data.utf8)),
            object["type"] as? String == "error"
        {
            throw AgentError.stream(object["error"] as? [String: Any], provider: provider)
        }
        return try accumulator.apply(event)
    }

    /// The `error.type` of an error body (a short identifier such as `overloaded_error`), never its message.
    private static func errorType(in bytes: URLSession.AsyncBytes) async -> String? {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 65_536 { break }
            }
        } catch {
            return nil
        }
        let type = (parseJSONObject(data)?["error"] as? [String: Any])?["type"] as? String
        guard let type, type.count <= 64, type.allSatisfy({ $0.isLetter || $0 == "_" }) else { return nil }
        return type
    }
}

private final class MessagesNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
