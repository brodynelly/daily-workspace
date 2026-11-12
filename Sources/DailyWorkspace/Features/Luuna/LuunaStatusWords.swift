import DailyCore
import SwiftUI

/// Luuna read states in words, with their tones. Only a live, authenticated connection is green; a successful read
/// of one resource is not, and neither is any value retained from an earlier read.
enum LuunaStatusWords {
    /// The connection as a whole: success "Connected" only when health and the protected project list both
    /// succeeded in this session.
    @MainActor
    static func connection(_ luuna: LuunaStore) -> ObservedSource {
        if luuna.isConnected {
            return ObservedSource(tone: .success, text: "Connected to \(luuna.origin)")
        }
        if !luuna.hasToken, luuna.connectionState == .unavailable(.notChecked) {
            return ObservedSource(tone: .attention, text: "Not connected: no token is saved for \(luuna.origin)")
        }
        let words = describe(luuna.connectionState, origin: luuna.origin)
        return ObservedSource(tone: words.tone, text: "Not connected: \(words.text)")
    }

    /// One read's failure (or success) as a tone and a sentence fragment.
    static func describe(_ state: LuunaReadState, origin: LuunaOrigin) -> ObservedSource {
        switch state {
        case .populated: return ObservedSource(tone: .neutral, text: "read")
        case .empty: return ObservedSource(tone: .neutral, text: "read; it holds nothing")
        case .uninitialized: return ObservedSource(tone: .neutral, text: "not set up in this runtime")
        case .unsupported: return ObservedSource(tone: .neutral, text: "this runtime does not serve that read")
        case .unauthorized:
            return ObservedSource(tone: .attention, text: "the token is missing or was refused (Settings › Luuna)")
        case .refused(let refusal):
            let reason = refusal.reason.map { ": \($0)" } ?? ""
            return ObservedSource(tone: .danger, text: "refused (HTTP \(refusal.status))\(reason)")
        case .partial: return ObservedSource(tone: .attention, text: "the answer could not be read")
        case .unavailable(let reason): return unavailable(reason, origin: origin)
        }
    }

    private static func unavailable(_ reason: LuunaUnavailableReason, origin: LuunaOrigin) -> ObservedSource {
        switch reason {
        case .notChecked: return ObservedSource(tone: .neutral, text: "not checked yet")
        case .cannotConnect:
            return ObservedSource(tone: .interrupted, text: "nothing answered at \(origin); is the runtime running?")
        case .timedOut: return ObservedSource(tone: .interrupted, text: "the runtime did not answer in time")
        case .redirectRefused:
            return ObservedSource(
                tone: .attention, text: "\(origin) answered with a redirect, which is never followed")
        case .busy: return ObservedSource(tone: .interrupted, text: "the runtime is busy (HTTP 429)")
        case .shuttingDown(let words): return ObservedSource(tone: .interrupted, text: "the runtime said: \(words)")
        case .serverError(let status): return ObservedSource(tone: .danger, text: "server error (HTTP \(status))")
        case .transport(let code):
            return ObservedSource(tone: .interrupted, text: "connection failed (URL error \(code))")
        case .otherAuthority:
            return ObservedSource(tone: .attention, text: "the project is bound to another runtime than \(origin)")
        }
    }
}

/// The last-observed line for one Luuna resource: when it was last read, and a stale note when the latest read
/// failed and an older value is still on screen.
struct LuunaObservedNote<Value>: View {
    let name: String
    let observation: LuunaObservation<Value>
    let origin: LuunaOrigin

    var body: some View {
        if observation.isShowingRetainedValue, let last = observation.lastSuccessAt {
            let words = LuunaStatusWords.describe(observation.state, origin: origin)
            ReasonNote(
                "Stale: \(name) as last read at \(ObservedSource.time(last)). The latest read failed: \(words.text).",
                tone: .interrupted)
        } else if let observed = observation.lastSuccessAt {
            Text("\(name) last observed \(ObservedSource.time(observed))")
                .textRole(.caption, lineBox: false)
                .foregroundStyle(Theme.inkMuted)
        } else if !observation.state.isSuccess, observation.observedAt != nil {
            let words = LuunaStatusWords.describe(observation.state, origin: origin)
            ReasonNote("\(name) could not be read: \(words.text).", tone: words.tone)
        }
    }
}
