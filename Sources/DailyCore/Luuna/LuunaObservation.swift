import Foundation

/// Why the Luuna CLI could not read the selected runtime. The app supplies the wording.
public enum LuunaUnavailableReason: Equatable, Sendable {
    /// No read has completed in this connection session yet.
    case notChecked
    /// Nothing answered at the origin: refused, unreachable, or the connection dropped.
    case cannotConnect
    case timedOut
    /// A runtime redirect is never followed.
    case redirectRefused
    /// The runtime is at its limit of active runs or streams.
    case busy
    /// HTTP 503 carrying the runtime's own short reason, such as `runtime is shutting down`.
    case shuttingDown(String)
    /// A runtime 5xx response.
    case serverError(status: Int)
    /// A transport failure not listed above, as its error code.
    case transport(code: Int)
    /// The project is bound to a different runtime origin than the one this session reads.
    case otherAuthority
}

/// The runtime declined a request. `reason` is present only when the CLI supplies a bounded,
/// validated reason; credentials and untrusted response bodies are never surfaced.
public struct LuunaRefusal: Equatable, Sendable {
    public let status: Int
    public let reason: String?

    public init(status: Int, reason: String?) {
        self.status = status
        self.reason = reason
    }
}

/// The source states of AGENTS.md and SYSTEM-INVENTORY §8.3, for one Luuna read. Each maps one-to-one onto the
/// app-wide `SourceState`; `partial` is the "partial/stale" state.
public enum LuunaReadState: Equatable, Sendable {
    /// This runtime build does not serve the endpoint (404 without a record-specific reason, 405, 501), or what
    /// answered is not a runtime this app can read.
    case unsupported
    /// No token, or the runtime rejected it (401) or denied the read (403).
    case unauthorized
    case unavailable(LuunaUnavailableReason)
    /// The runtime answered, but the thing read was never set up (for example components not enabled).
    case uninitialized
    case refused(LuunaRefusal)
    /// A response arrived but could not be decoded; the last good value, if any, is still shown.
    case partial
    /// A successful read with nothing in it.
    case empty
    case populated

    /// True for a read that succeeded in the current session (`populated`, `empty` or `uninitialized`).
    public var isSuccess: Bool {
        switch self {
        case .populated, .empty, .uninitialized: return true
        default: return false
        }
    }
}

/// One observed Luuna resource: the state of the latest read, plus the last good value, which survives later
/// failures so the UI can show it as historical with its time.
public struct LuunaObservation<Value> {
    public private(set) var state: LuunaReadState
    /// The value from the last successful read. Kept across failures; never replaced by a failed read.
    public private(set) var value: Value?
    /// When the latest read finished, successful or not. Nil before the first read.
    public private(set) var observedAt: Date?
    /// When `value` was received.
    public private(set) var lastSuccessAt: Date?

    public init() {
        state = .unavailable(.notChecked)
    }

    /// Records a successful read. `state` is `populated` unless the resource says otherwise (`empty`,
    /// `uninitialized`).
    public mutating func recordSuccess(_ value: Value, state: LuunaReadState = .populated, at date: Date) {
        precondition(state.isSuccess, "A successful read cannot have a failure state.")
        self.value = value
        self.state = state
        observedAt = date
        lastSuccessAt = date
    }

    /// Records a failed read. The last good value and its time are kept.
    public mutating func recordFailure(_ state: LuunaReadState, at date: Date) {
        precondition(!state.isSuccess, "A failed read cannot have a success state.")
        self.state = state
        observedAt = date
    }

    /// A value is on screen, but the latest read did not confirm it.
    public var isShowingRetainedValue: Bool { value != nil && !state.isSuccess }
}

extension LuunaObservation: Equatable where Value: Equatable {}
extension LuunaObservation: Sendable where Value: Sendable {}

/// How a read failed. Thrown by `LuunaRuntimeReading`; each case has exactly one `LuunaReadState`.
public enum LuunaReadFailure: Error, Equatable, Sendable {
    case unsupported
    case unauthorized
    case unavailable(LuunaUnavailableReason)
    case refused(LuunaRefusal)
    /// A success status whose body is not the expected shape.
    case undecodable

    public var state: LuunaReadState {
        switch self {
        case .unsupported: return .unsupported
        case .unauthorized: return .unauthorized
        case .unavailable(let reason): return .unavailable(reason)
        case .refused(let refusal): return .refused(refusal)
        case .undecodable: return .partial
        }
    }

}
