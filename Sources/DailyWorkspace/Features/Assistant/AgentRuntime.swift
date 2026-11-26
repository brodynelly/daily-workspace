import DailyCore
import Foundation

/// A lifecycle event of one Assistant run, for observers (hooks), the run summary and the unified log.
/// Events carry names, counts and timings only: never the question, note text, tool arguments or answers
/// (OpenTelemetry GenAI's "no content by default").
enum AgentRunEvent: Equatable, Sendable {
    /// Model request number `request` (1-based) of the run is about to be sent.
    case requestStarted(request: Int)
    case requestFinished(request: Int, stopReason: String?, model: String?, usage: AgentUsage, duration: TimeInterval)
    case retrying(AgentRetryEvent)
    case toolStarted(name: String)
    case toolFinished(name: String, isError: Bool, timedOut: Bool, truncated: Bool, duration: TimeInterval)
    case finished(AgentRunSummary)
}

/// What one run did, without content. Kept for the last run and logged when the run ends.
struct AgentRunSummary: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case answered
        case failed(AgentError.Kind)
        case cancelled
        case unknownFailure
    }

    /// `chat` or `draft`.
    var profile: String
    var outcome: Outcome = .answered
    var requests = 0
    var toolRounds = 0
    var toolCalls = 0
    var toolErrors = 0
    var toolTimeouts = 0
    var truncatedResults = 0
    var retries = 0
    var usage = AgentUsage()
    var duration: TimeInterval = 0

    var outcomeName: String {
        switch outcome {
        case .answered: return "answered"
        case .failed(let kind): return "failed:\(kind)"
        case .cancelled: return "cancelled"
        case .unknownFailure: return "failed:unknown"
        }
    }
}

/// Accumulates one run's summary from its events.
@MainActor
final class AgentRunTrace {
    private(set) var summary: AgentRunSummary
    private let started = ContinuousClock.now

    init(profile: String) {
        summary = AgentRunSummary(profile: profile)
    }

    func record(_ event: AgentRunEvent) {
        switch event {
        case .requestStarted: summary.requests += 1
        case .requestFinished(_, _, _, let usage, _): summary.usage += usage
        case .retrying: summary.retries += 1
        case .toolStarted: summary.toolCalls += 1
        case .toolFinished(_, let isError, let timedOut, let truncated, _):
            if isError { summary.toolErrors += 1 }
            if timedOut { summary.toolTimeouts += 1 }
            if truncated { summary.truncatedResults += 1 }
        case .finished: break
        }
        summary.duration = (ContinuousClock.now - started).timeInterval
    }

    func noteToolRound() {
        summary.toolRounds += 1
    }
}

/// The runtime limits the Assistant applies, built from `AssistantRuntimeSettings` (settings.json) so every
/// value is in range. Tests construct it directly.
struct AgentRuntimeLimits: Equatable, Sendable {
    var maxToolRounds = AssistantRuntimeSettings.defaultMaxToolRounds
    var maxOutputTokens = AssistantRuntimeSettings.defaultMaxOutputTokens
    var chatEffort = AgentEffort.low
    var draftEffort = AgentEffort.medium
    var retry = AgentRetryPolicy()
    /// Longest one tool call may take before the model is told its source is unknown right now.
    var toolTimeout: TimeInterval = AssistantRuntimeSettings.defaultToolTimeoutSeconds
    /// Largest `tool_result` sent to the model, in UTF-8 bytes (about a quarter as many tokens).
    var maxToolResultBytes = AssistantRuntimeSettings.defaultMaxToolResultBytes
    /// The tools offered to the model. Calls to any other tool are refused.
    var enabledTools: Set<AssistantTool> = Set(AssistantTool.allCases)

    init() {}

    init(_ settings: AssistantRuntimeSettings) {
        let settings = settings.validated
        maxToolRounds = settings.maxToolRounds
        maxOutputTokens = settings.maxOutputTokens
        chatEffort = AgentEffort(rawValue: settings.chatEffort) ?? .low
        draftEffort = AgentEffort(rawValue: settings.draftEffort) ?? .medium
        retry.maxRetries = settings.maxRetries
        toolTimeout = settings.toolTimeoutSeconds
        maxToolResultBytes = settings.maxToolResultBytes
        let disabled = Set(settings.disabledTools)
        enabledTools = Set(AssistantTool.allCases.filter { !disabled.contains($0.rawValue) })
    }
}

extension AssistantTool {
    /// Definitions of `enabled` tools, sorted by name and rendered the same way every time.
    static func enabledDefinitions(_ enabled: Set<AssistantTool>) -> [JSONValue] {
        allCases.filter { enabled.contains($0) }.sorted { $0.rawValue < $1.rawValue }.map(\.definition)
    }
}

/// A tool call that ran past its deadline. The model is told its source is unknown, never that it is empty.
struct ToolTimeout: Error, Equatable {
    let seconds: TimeInterval
}

enum AgentDeadline {
    /// Run `operation`, failing with `ToolTimeout` once `seconds` pass. The operation is cancelled on timeout,
    /// and the caller is released even if the operation ignores cancellation (a stalled adapter cannot hold a
    /// turn). Cancelling the caller cancels the operation.
    static func run<T: Sendable>(
        seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = DeadlineGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                guard gate.install(continuation) else { return }
                let work = Task {
                    do {
                        gate.resume(.success(try await operation()))
                    } catch {
                        gate.resume(.failure(error))
                    }
                }
                let timer = Task {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, min(seconds, 3_600)) * 1_000_000_000))
                    gate.resume(.failure(ToolTimeout(seconds: seconds)))
                }
                gate.attach(work: work, timer: timer)
            }
        } onCancel: {
            gate.resume(.failure(CancellationError()))
        }
    }
}

/// Resumes a continuation exactly once and then cancels the work and the timer.
private final class DeadlineGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?
    private var done = false
    private var tasks: [Task<Void, Never>] = []

    /// False when the gate already finished (cancelled before the continuation existed); it is resumed here.
    func install(_ continuation: CheckedContinuation<T, Error>) -> Bool {
        let early: Result<T, Error>? = lock.withLock {
            if done { return pending }
            self.continuation = continuation
            return nil
        }
        if let early {
            continuation.resume(with: early)
            return false
        }
        return true
    }

    func attach(work: Task<Void, Never>, timer: Task<Void, Never>) {
        let finished: Bool = lock.withLock {
            if !done { tasks = [work, timer] }
            return done
        }
        if finished {
            work.cancel()
            timer.cancel()
        }
    }

    func resume(_ result: Result<T, Error>) {
        let (continuation, tasks): (CheckedContinuation<T, Error>?, [Task<Void, Never>]) = lock.withLock {
            guard !done else { return (nil, []) }
            done = true
            let taken = (self.continuation, self.tasks)
            if self.continuation == nil { pending = result }
            self.continuation = nil
            self.tasks = []
            return taken
        }
        continuation?.resume(with: result)
        for task in tasks { task.cancel() }
    }
}

extension Duration {
    /// This duration in seconds.
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
