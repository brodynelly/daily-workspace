import Foundation

/// Sends one Messages API request and streams the response. Unlike `ChatTransport`, it carries tool calls,
/// thinking blocks and stop reasons, which the Assistant's tool loop needs.
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
    enum Kind: Equatable, Sendable {
        case missingKey, keychain, unauthorized, forbidden, notFound, rateLimited, overloaded, server
        case badRequest, tooLarge, timedOut, offline, network, incomplete, refused, truncated, toolLimit
        case invalidDraft, busy, disabled
    }

    let kind: Kind
    let message: String

    init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    var errorDescription: String? { message }

    static func http(status: Int, errorType: String?, retryAfter: String?) -> AgentError {
        switch status {
        case 400: return AgentError(.badRequest, "Anthropic rejected the request as invalid (HTTP 400).")
        case 401: return AgentError(.unauthorized, "Anthropic rejected the API key. Check it in Settings → AI.")
        case 403:
            return AgentError(.forbidden, "This API key isn't allowed to use the model. Check your Anthropic account.")
        case 404:
            return AgentError(.notFound, "Anthropic didn't recognize the model. Check the model in Settings → AI.")
        case 413: return AgentError(.tooLarge, "The conversation is too large to send. Clear it and try again.")
        case 429:
            let wait =
                retryAfter.flatMap(Int.init).map { " Try again in \($0) seconds." } ?? " Wait a moment and try again."
            return AgentError(.rateLimited, "Anthropic's rate limit was reached." + wait)
        case 529: return overloadedError
        case 500..<600:
            if errorType == "overloaded_error" { return overloadedError }
            return AgentError(.server, "Anthropic had a server problem (HTTP \(status)). Try again in a moment.")
        default: return AgentError(.server, "Anthropic returned HTTP \(status).")
        }
    }

    /// An `error` event in the middle of a stream. Only its `type` is read.
    static func stream(_ error: [String: Any]?) -> AgentError {
        switch error?["type"] as? String {
        case "overloaded_error": return overloadedError
        case "rate_limit_error": return http(status: 429, errorType: nil, retryAfter: nil)
        case "authentication_error": return http(status: 401, errorType: nil, retryAfter: nil)
        case "permission_error": return http(status: 403, errorType: nil, retryAfter: nil)
        case "invalid_request_error": return http(status: 400, errorType: nil, retryAfter: nil)
        case "request_too_large": return http(status: 413, errorType: nil, retryAfter: nil)
        default: return AgentError(.server, "Anthropic stopped the response with an error. Try again in a moment.")
        }
    }

    static func network(_ error: URLError) -> AgentError {
        switch error.code {
        case .timedOut: return AgentError(.timedOut, "Anthropic didn't respond within 120 seconds. Try again.")
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return AgentError(.offline, "The Mac is offline. Connect to the internet and try again.")
        default: return AgentError(.network, "Couldn't reach Anthropic. Check your connection and try again.")
        }
    }

    private static let overloadedError = AgentError(
        .overloaded, "Anthropic is overloaded right now. Try again in a moment.")
}

/// The Anthropic Messages API over HTTPS, streamed as server-sent events.
struct AnthropicClient: AgentTransport {
    static let defaultEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    /// Server-side refusal fallbacks in the `fallbacks: "default"` form.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    var endpoint = defaultEndpoint
    /// Longest wait for the next bytes of a response.
    var idleTimeout: TimeInterval = 120
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
        // Ephemeral: no URL cache, cookies or credentials persist for this traffic.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.timeoutIntervalForResource = totalTimeout
        configuration.urlCache = nil
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest(for: request, apiKey: apiKey))
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let errorType = await Self.errorType(in: bytes)
                Log.chat.error(
                    "Anthropic returned HTTP \(status, privacy: .public) \(errorType ?? "-", privacy: .public)")
                throw AgentError.http(
                    status: status, errorType: errorType, retryAfter: http?.value(forHTTPHeaderField: "retry-after"))
            }
            var parser = SSEParser()
            var accumulator = MessageStreamAccumulator()
            for try await byte in bytes {
                guard let event = parser.push(byte) else { continue }
                if let update = try accumulator.apply(event) { await onUpdate(update) }
            }
            if let event = parser.finish(), let update = try accumulator.apply(event) { await onUpdate(update) }
            try Task.checkCancellation()
            guard accumulator.isComplete else {
                throw AgentError(.incomplete, "The response ended before it finished. Try again.")
            }
            return accumulator.finalResponse()
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            Log.chat.error("Anthropic request failed: \(Log.code(error), privacy: .public)")
            throw AgentError.network(error)
        }
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
