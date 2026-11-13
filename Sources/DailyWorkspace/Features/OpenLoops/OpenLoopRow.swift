import DailyCore
import SwiftUI

/// One open loop with its native status, source and dates. Only local tasks and reminders accept writes.
struct OpenLoopRow: View {
    let loop: OpenLoop

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var loops: OpenLoopsStore
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var reminders: RemindersService
    @State private var editing: TaskItem?
    @State private var deleting: TaskItem?

    var body: some View {
        RecordRow {
            HStack(alignment: .top, spacing: Space.s3) {
                // Reserved for every row, so titles line up whether or not the owner accepts completion here.
                ZStack { leading }.frame(width: Metrics.controlSm, height: Metrics.controlSm)
                VStack(alignment: .leading, spacing: Space.s1Half) {
                    Text(verbatim: loop.title)
                        .textRole(.body, lineBox: false)
                        .foregroundStyle(loop.isDoneInSource ? Theme.inkMuted : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    chips
                    if !meta.isEmpty {
                        Text(verbatim: meta.joined(separator: " · "))
                            .foregroundStyle(Theme.inkMuted)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
        }
        .contextMenu { menu }
        .sheet(item: $editing) { TaskEditSheet(task: $0) }
        .confirmationDialog(
            "Delete “\(deleting?.title ?? "")” from tasks.json?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let deleting { tasks.delete(deleting) }
            }
        } message: {
            Text("You can undo right after.")
        }
    }

    private var actions: [LoopAction] { loop.ownerActions }

    // MARK: Parts

    @ViewBuilder private var leading: some View {
        if actions.contains(.complete) || actions.contains(.reopen) {
            RowIconButton(
                symbol: loop.isDoneInSource ? "checkmark.circle.fill" : "circle",
                label: loop.isDoneInSource ? "Reopen \(loop.title)" : "Complete \(loop.title)"
            ) {
                if let task = loops.task(for: loop) { tasks.toggle(task) }
            }
        } else if actions.contains(.completeReminder) {
            RowIconButton(symbol: "circle", label: "Complete \(loop.title) in Apple Reminders") {
                guard let item = loops.reminder(for: loop) else { return }
                Task { await reminders.complete(item) }
            }
        }
    }

    private var chips: some View {
        HStack(spacing: Space.s2) {
            if !loop.nativeStatus.isEmpty {
                StatusBadge(loop.nativeStatus, tone: LoopTone.tone(for: loop))
            }
            Tag(loop.authority.ownerName)
            if let project = loop.project { Tag("project:\(project)") }
        }
    }

    /// The owner's dates, a local task's linked note, or a reminder's list.
    private var meta: [String] {
        var parts = loop.dateLines
        switch loop.authority {
        case .reminders: parts += loop.labels.prefix(1).map { "\($0) list" }
        case .local: parts += loop.sourcePath.map { ["Linked to \($0)"] } ?? []
        case .luuna, .mail: break
        }
        return parts
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: Space.s1) {
            if let note = loop.authority == .local ? loop.sourcePath : nil {
                RowIconButton(symbol: "doc.text", label: "Open linked note \(note)") { model.openNote(note) }
            }
            if actions.contains(.edit) {
                RowIconButton(symbol: "pencil", label: "Edit \(loop.title)") { editing = loops.task(for: loop) }
            }
            if actions.contains(.delete) {
                RowIconButton(symbol: "trash", label: "Delete \(loop.title)") { deleting = loops.task(for: loop) }
            }
        }
    }

    @ViewBuilder private var menu: some View {
        if actions.contains(.edit) { Button("Edit…") { editing = loops.task(for: loop) } }
        if actions.contains(.delete) {
            Divider()
            Button("Delete…", role: .destructive) { deleting = loops.task(for: loop) }
        }
    }
}

/// A 28 pt icon button for a row: no chrome until hovered, then the fill. Nothing lifts or scales.
struct RowIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isEnabled ? Theme.inkBody : Theme.inkDisabled)
                .frame(width: Metrics.controlSm, height: Metrics.controlSm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(hovered && isEnabled ? Theme.fill : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
