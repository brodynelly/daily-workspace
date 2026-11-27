import Foundation

/// When and how long to wait before sending a failed model request again. The defaults follow the official
/// Anthropic SDKs: 2 retries, `min(0.5 × 2ⁿ, 8)` seconds shortened by up to 25 % at random, and the server's
/// `retry-after-ms`/`retry-after` and `x-should-retry` advice when it gives any.
struct AgentRetryPolicy: Equatable, Sendable {
    var maxRetries = 2
    var initialDelay: TimeInterval = 0.5
    var maxDelay: TimeInterval = 8
    /// Longest server-requested wait honored. A longer one (for example a spent monthly cap) fails at once
    /// with the server's message, so a person is never left watching a silent spinner.
    var maxServerDelay: TimeInterval = 60

    static let none = AgentRetryPolicy(maxRetries: 0)

    /// Kinds that a moment's wait can fix. Bad requests, keys, permissions, refusals and the offline state can't.
    static let transientKinds: Set<AgentError.Kind> = [
        .rateLimited, .overloaded, .server, .timedOut, .network, .incomplete,
    ]

    func isRetryable(_ error: AgentError) -> Bool {
        if let shouldRetry = error.shouldRetry { return shouldRetry }
        // A 429 without `retry-after` is a spent cap, not a burst limit: it keeps failing until access resumes.
        if error.kind == .rateLimited, error.retryAfter == nil { return false }
        return Self.transientKinds.contains(error.kind)
    }

    /// Seconds to wait before retry number `attempt` (0 for the first retry), or nil when the server asked for a
    /// wait longer than `maxServerDelay`. `jitter` is in 0..<1.
    func delay(forRetry attempt: Int, error: AgentError, jitter: Double) -> TimeInterval? {
        if let requested = error.retryAfter {
            return requested <= maxServerDelay ? max(0, requested) : nil
        }
        let exponent = Double(max(0, min(attempt, 30)))
        let base = min(initialDelay * pow(2, exponent), maxDelay)
        return max(0, base * (1 - 0.25 * min(max(jitter, 0), 1)))
    }
}

/// One retry, as reported to run observers. No request or response content.
struct AgentRetryEvent: Equatable, Sendable {
    /// 1 for the first retry.
    var attempt: Int
    var kind: AgentError.Kind
    var delay: TimeInterval
}

/// Wraps any `AgentTransport` with `AgentRetryPolicy`. A request is retried only while nothing from it has been
/// streamed to the caller, so a retry can never repeat or splice text the person already saw.
struct RetryingAgentTransport: AgentTransport {
    let base: AgentTransport
    var policy: AgentRetryPolicy
    var sleep: @Sendable (TimeInterval) async throws -> Void = { try await RetryingAgentTransport.taskSleep($0) }
    var jitter: @Sendable () -> Double = { Double.random(in: 0..<1) }
    var onRetry: @Sendable (AgentRetryEvent) async -> Void = { _ in }

    func send(
        _ request: AgentRequest, apiKey: String, onUpdate: @escaping @Sendable (AgentStreamUpdate) async -> Void
    ) async throws -> AgentResponse {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let progress = StreamProgressFlag()
            do {
                return try await base.send(request, apiKey: apiKey) { update in
                    progress.mark()
                    await onUpdate(update)
                }
            } catch let error as AgentError {
                guard attempt < policy.maxRetries, !progress.isMarked, policy.isRetryable(error),
                    let wait = policy.delay(forRetry: attempt, error: error, jitter: jitter())
                else { throw error }
                attempt += 1
                let kind = String(describing: error.kind)
                Log.assistant.info("Model request retry \(attempt, privacy: .public) after \(kind, privacy: .public)")
                await onRetry(AgentRetryEvent(attempt: attempt, kind: error.kind, delay: wait))
                try await sleep(wait)
            }
        }
    }

    static func taskSleep(_ seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(min(seconds, 3_600) * 1_000_000_000))
    }
}

/// Set once anything streamed: a thread-safe flag shared with the transport's update callback.
private final class StreamProgressFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false

    func mark() { lock.withLock { marked = true } }
    var isMarked: Bool { lock.withLock { marked } }
}
