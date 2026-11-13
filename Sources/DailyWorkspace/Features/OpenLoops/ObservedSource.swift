import DailyCore
import SwiftUI

/// One source's latest observation in words, led by a tone: what was read, or exactly why it was not. An
/// inaccessible source never reads as "nothing open", and a read that failed after an earlier success says it is
/// showing the last good read and when that was.
struct ObservedSource: Equatable {
    let tone: Tone
    let text: String
    /// Problems listed under the line (a partial read's issues).
    var issues: [String] = []
    /// When the shown data was last read, for partial and stale reads.
    var lastRead: Date?

    /// - Parameters:
    ///   - name: the source as the UI names it (`Local`, `Hubs`).
    ///   - summary: what a readable read holds (`3 open`, `nothing open`, `12 hubs`).
    ///   - notSetUp: what `uninitialized` means for this source.
    init<Value>(_ name: String, observation: SourceObservation<Value>?, summary: String, notSetUp: String? = nil) {
        guard let observation else {
            self.init(tone: .neutral, text: "\(name): not read yet")
            return
        }
        let state = observation.state
        if !state.isReadable, let last = observation.lastSuccessAt {
            let failure = Self.failure(name, state, notSetUp: notSetUp)
            self.init(tone: failure.tone, text: "\(failure.text). Showing the last read", lastRead: last)
            return
        }
        switch state {
        case .partial(let issues):
            self.init(
                tone: .attention, text: "\(name): \(summary), but some records could not be read",
                issues: issues.map(\.description), lastRead: observation.lastSuccessAt ?? observation.observedAt)
        case .empty, .populated:
            self.init(tone: .neutral, text: "\(name): \(summary)")
        case .unsupported, .unauthorized, .unavailable, .uninitialized, .refused:
            self = Self.failure(name, state, notSetUp: notSetUp)
        }
    }

    init(tone: Tone, text: String, issues: [String] = [], lastRead: Date? = nil) {
        self.tone = tone
        self.text = text
        self.issues = issues
        self.lastRead = lastRead
    }

    private static func failure(_ name: String, _ state: SourceState, notSetUp: String?) -> ObservedSource {
        switch state {
        case .unsupported: return ObservedSource(tone: .neutral, text: "\(name) is not supported on this Mac")
        case .unauthorized: return ObservedSource(tone: .attention, text: "\(name) not authorized: access was denied")
        case .unavailable(let reason): return ObservedSource(tone: .interrupted, text: "\(name) unavailable: \(reason)")
        case .uninitialized:
            return ObservedSource(tone: .neutral, text: "\(name) not set up" + (notSetUp.map { ": \($0)" } ?? ""))
        case .refused(let reason): return ObservedSource(tone: .attention, text: "\(name) refused: \(reason)")
        case .partial, .empty, .populated: return ObservedSource(tone: .neutral, text: name)
        }
    }

    /// `10:42`, or `12 Nov 2026 at 10:42` for another day.
    static func time(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A `ObservedSource` as a line: the tone's mark and the words, then "last read …" and any issues under it.
struct ObservedSourceLine: View {
    let status: ObservedSource
    /// Issues shown before "and N more".
    var issueLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                ToneMark(tone: status.tone).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(lineText)
                    .foregroundStyle(Theme.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(status.issues.prefix(issueLimit).enumerated()), id: \.offset) { _, issue in
                Text(verbatim: issue)
                    .font(TextRole.caption.font)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Metrics.markSize + Space.s2)
            }
            if status.issues.count > issueLimit {
                Text("and \(status.issues.count - issueLimit) more")
                    .font(TextRole.caption.font)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.leading, Metrics.markSize + Space.s2)
            }
        }
        .textRole(.bodySmall, lineBox: false)
        .accessibilityElement(children: .combine)
    }

    private var lineText: String {
        guard let last = status.lastRead else { return status.text }
        return "\(status.text) · last read \(ObservedSource.time(last))"
    }
}
