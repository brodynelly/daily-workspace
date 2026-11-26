import DailyCore
import SwiftUI

/// The Assistant's vault changes: what waits for review (apply or reject, with the exact line diff) and what was
/// applied (undo while the note still holds what was written). Every action re-checks the note on disk.
struct AgentChangesView: View {
    @ObservedObject var changes: VaultChanges
    var openNote: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            SectionHeading("Vault changes") {
                Button("Done") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
            if let storageError = changes.storageError { ReasonNote(storageError, tone: .danger) }
            if let error { ReasonNote(error, tone: .danger) }
            HStack(alignment: .top, spacing: Space.s4) {
                list.frame(width: 280)
                VerticalHairline()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(Space.s5)
        .frame(minWidth: 820, minHeight: 520)
        .background(Theme.surfaceOverlay)
        .onAppear { selection = selection ?? changes.pending.first?.id ?? changes.history.first?.id }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Waiting for review (\(changes.pending.count))")
                    .textRole(.label, lineBox: false)
                    .foregroundStyle(Theme.ink)
                if changes.pending.isEmpty {
                    Text("Nothing is waiting.").textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
                }
                ForEach(changes.pending) { row($0) }
                Text("History").textRole(.label, lineBox: false).foregroundStyle(Theme.ink).padding(.top, Space.s3)
                ForEach(changes.history) { row($0) }
            }
        }
    }

    private func row(_ change: VaultChange) -> some View {
        Button {
            selection = change.id
            error = nil
        } label: {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s2) {
                    StatusBadge(Self.statusText(change), tone: Self.tone(change))
                    Text(verbatim: Self.counts(change)).textRole(.caption, lineBox: false)
                }
                Text(verbatim: change.path).textRole(.bodySmall, lineBox: false).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s2)
            .surface(
                selection == change.id ? Theme.controlSelected : .clear,
                edge: selection == change.id ? Theme.borderStrong : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        if let change = changes.changes.first(where: { $0.id == selection }) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(verbatim: change.path)
                    .textRole(.bodyStrong, lineBox: false)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                Text(verbatim: Self.provenance(change)).textRole(.caption, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                if !change.summary.isEmpty {
                    Text(verbatim: "Why: \(change.summary)")
                        .textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkBody)
                }
                if let failure = change.failure { ReasonNote(failure, tone: .danger) }
                AgentDiffView(diff: LineDiff(before: change.before ?? "", after: change.after))
                actions(change)
            }
        } else {
            EmptyState("Choose a change", description: "Pick a change to see exactly what it does.", boxed: true)
        }
    }

    @ViewBuilder private func actions(_ change: VaultChange) -> some View {
        HStack {
            Button("Open note") { openNote(change.path) }.buttonStyle(.secondary)
                .disabled(change.status != .applied && change.before == nil)
            Spacer()
            switch change.status {
            case .pending:
                Button("Reject") { changes.reject(change.id) }.buttonStyle(.secondary)
                Button("Apply to vault") { act { try changes.apply(change.id) } }.buttonStyle(.primary)
            case .applied where change.canUndo:
                Button("Undo") { act { try changes.undo(change.id) } }.buttonStyle(.secondary)
            case .applied:
                Text("A new note can't be undone here; remove it in Obsidian if you don't want it.")
                    .textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
            default:
                EmptyView()
            }
        }
    }

    private func act(_ action: () throws -> Void) {
        do {
            try action()
            error = nil
        } catch {
            self.error = VaultChanges.describe(error)
        }
    }

    static func statusText(_ change: VaultChange) -> String {
        switch change.status {
        case .pending: return "Review"
        case .applied: return change.autoApplied ? "Auto-applied" : "Applied"
        case .rejected: return "Rejected"
        case .undone: return "Undone"
        case .failed: return "Failed"
        }
    }

    static func tone(_ change: VaultChange) -> Tone {
        switch change.status {
        case .pending: return .attention
        case .applied: return .success
        case .failed: return .danger
        case .rejected, .undone: return .neutral
        }
    }

    static func counts(_ change: VaultChange) -> String {
        let counts = change.lineCounts
        let kind: String
        switch change.kind {
        case .create: kind = "new note"
        case .edit: kind = "edit"
        case .append: kind = "append"
        }
        return "\(kind) · +\(counts.added) −\(counts.removed)"
    }

    static func provenance(_ change: VaultChange) -> String {
        let date = change.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "From \(change.origin), \(date)"
    }
}

/// A unified line diff: removed lines on the danger ground, added on the success ground, unchanged dimmed.
struct AgentDiffView: View {
    let diff: LineDiff

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                    Self.render(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(Space.s2)
        }
        .frame(minHeight: 240, maxHeight: .infinity)
        .surface(Theme.surfaceRaised, edge: Theme.separator)
        .accessibilityLabel("Changes: \(diff.added) lines added, \(diff.removed) removed")
    }

    @ViewBuilder private static func render(_ line: LineDiff.Line) -> some View {
        switch line {
        case .same(let content):
            lineText(" ", content).foregroundStyle(Theme.inkMuted)
        case .removed(let content):
            lineText("−", content).background(Theme.dangerSoft)
        case .added(let content):
            lineText("+", content).background(Theme.successSoft)
        }
    }

    private static func lineText(_ mark: String, _ line: String) -> some View {
        Text(verbatim: "\(mark) \(line)")
            .font(TextRole.monoCaption.font)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
