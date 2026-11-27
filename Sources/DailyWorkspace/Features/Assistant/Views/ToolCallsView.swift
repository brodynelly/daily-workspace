import SwiftUI

/// An answer's lookups behind a quiet disclosure: the count of lookups and of things cited, then each lookup.
struct ToolCallsDisclosure: View {
    let calls: [AssistantToolCall]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Bool

    init(calls: [AssistantToolCall], expanded: Bool = false) {
        self.calls = calls
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Button {
                withAnimation(Motion.stateChange(reduceMotion: reduceMotion)) { expanded.toggle() }
            } label: {
                HStack(spacing: Space.s1Half) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(summary).textRole(.bodySmall, lineBox: false)
                }
                .foregroundStyle(Theme.inkMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(summary))
            .accessibilityValue(Text(expanded ? "Expanded" : "Collapsed"))
            if expanded { ToolCallList(calls: calls, live: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.s3)
        .overlay(alignment: .top) { Hairline() }
    }

    private var summary: String {
        let cited = ToolCitation.unique(calls.flatMap(\.citations)).count
        let lookups = calls.count == 1 ? "1 lookup" : "\(calls.count) lookups"
        let failed = calls.filter(\.isError).count
        var parts = [lookups, cited == 1 ? "1 cited source" : "\(cited) cited sources"]
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }
}

/// Each lookup: the tool, its arguments verbatim, why it failed, and the record IDs and paths it returned.
/// `live` (while the turn runs) is compact: a lookup with no result yet shows as running, and finished ones
/// show how much they returned; the full list follows in the finished answer.
struct ToolCallList: View {
    let calls: [AssistantToolCall]
    var live = false

    var body: some View {
        VStack(alignment: .leading, spacing: live ? Space.s2 : Space.s3) {
            ForEach(calls) { call in
                ToolCallRow(call: call, live: live)
            }
        }
    }
}

private struct ToolCallRow: View {
    let call: AssistantToolCall
    let live: Bool

    private var running: Bool { live && !call.isError && call.citations.isEmpty }
    /// Record IDs first, then paths, each once.
    private var citations: [ToolCitation] {
        let unique = ToolCitation.unique(call.citations)
        return unique.filter { $0.kind == .record } + unique.filter { $0.kind == .path }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1Half) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(verbatim: call.name)
                    .font(TextRole.mono.font)
                    .foregroundStyle(Theme.ink)
                Text(verbatim: call.arguments)
                    .font(.system(size: TextRole.caption.size, design: .monospaced))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if running {
                    StatusBadge("running", tone: .active)
                } else if call.isError {
                    StatusBadge("failed", tone: .danger)
                } else if live {
                    Text(citations.count == 1 ? "1 to cite" : "\(citations.count) to cite")
                        .textRole(.caption, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            if let message = call.errorMessage {
                ReasonNote(message, tone: .danger)
            } else if !live, citations.isEmpty {
                Text("Returned nothing to cite.")
                    .textRole(.caption, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
            }
            if !live, !citations.isEmpty {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(citations, id: \.self) { CitationRow(citation: $0) }
                }
                .padding(.leading, Space.s3)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, live ? Space.s2 : Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.surfaceMuted))
    }
}

/// One cited path (mono, never truncated, with Open for notes) or record ID (`ShortId`, copyable).
struct CitationRow: View {
    let citation: ToolCitation

    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            switch citation.kind {
            case .path:
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .accessibilityHidden(true)
                Text(verbatim: citation.value)
                    .font(.system(size: TextRole.caption.size, design: .monospaced))
                    .foregroundStyle(Theme.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if Self.opensInNotes(citation.value) {
                    Button("Open") { model.openNote(citation.value) }
                        .buttonStyle(.workspace(.quiet, size: .small))
                        .help("Open \(citation.value) in Notes")
                }
            case .record:
                Image(systemName: "number")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .accessibilityHidden(true)
                ShortId(citation.value, kind: "record ID")
                Spacer(minLength: 0)
            }
        }
    }

    /// Only Markdown paths open in Notes; record IDs are shown separately.
    static func opensInNotes(_ path: String) -> Bool {
        VaultReadPolicy.noteExtensions.contains((path as NSString).pathExtension.lowercased())
    }
}
