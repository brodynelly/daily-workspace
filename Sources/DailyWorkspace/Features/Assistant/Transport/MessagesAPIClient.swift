import Foundation

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
