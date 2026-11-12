import DailyCore
import SwiftUI

/// Adds one item to an explicit owner: a local task to `tasks.json`, or a reminder to Apple Reminders. Nothing is
/// ever added to Org, Seeds or Plot from here. The form closes only after the owner accepted the item.
struct LoopComposer: View {
    enum Owner: Hashable {
        case task, reminder

        var title: String { self == .task ? "New task" : "New reminder" }

        /// Where the item goes, said before it is added.
        var destination: String {
            switch self {
            case .task: return "Saved to tasks.json in ~/.config/daily-workspace on this Mac."
            case .reminder: return "Added to your default Apple Reminders list. It syncs through your Apple account."
            }
        }
    }

    let owner: Owner
    let close: () -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var reminders: RemindersService
    @State private var title = ""
    @State private var dueToday = true
    @State private var saving = false

    var body: some View {
        Panel(owner.title, description: owner.destination) {
            Button("Cancel", action: close).buttonStyle(.workspace(.quiet, size: .small))
        } content: {
            if owner == .reminder, reminders.status != .authorized {
                RemindersAccessState()
            } else {
                HStack(spacing: Space.s3) {
                    BoxedTextField(owner == .task ? "Task title" : "Reminder title", text: $title, onSubmit: add)
                    Toggle(isOn: $dueToday) { Text("Due today") }.toggleStyle(.quiet)
                    Button("Add", action: add)
                        .buttonStyle(.primary)
                        .disabled(saving || trimmed.isEmpty)
                }
            }
        }
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        let text = trimmed
        guard !text.isEmpty, !saving else { return }
        switch owner {
        case .task:
            if tasks.add(title: text, due: dueToday ? model.today : nil) { finish() }
        case .reminder:
            saving = true
            Task {
                let added = await reminders.add(text, due: dueToday ? Date() : nil)
                saving = false
                if added { finish() }
            }
        }
    }

    private func finish() {
        title = ""
        close()
    }
}

/// Apple Reminders before it can be read, as a connect page: what access gives, then the one control that
/// grants it (the permission request, or System Settings once denied). Reuses `PermissionPrompt`'s wording.
struct RemindersAccessState: View {
    @EnvironmentObject private var reminders: RemindersService
    @EnvironmentObject private var loops: OpenLoopsStore

    private let kind = PermissionPrompt.Kind.reminders

    var body: some View {
        EmptyState(title, description: description, systemImage: "list.bullet.circle", boxed: true) {
            switch reminders.status {
            case .notRequested:
                Button("Allow Reminders Access…") {
                    Task {
                        await reminders.requestAccess()
                        await loops.refresh()
                    }
                }
                .buttonStyle(.primary)
            case .denied, .restricted:
                Button("Open System Settings") { kind.pane.open() }.buttonStyle(.secondary)
            case .authorized, .unavailable:
                EmptyView()
            }
        }
    }

    private var title: String {
        switch reminders.status {
        case .notRequested, .authorized: return "Connect Apple Reminders"
        case .denied: return "Reminders access is off"
        case .restricted: return "Reminders access is restricted"
        case .unavailable: return "Reminders is unavailable"
        }
    }

    private var description: String {
        switch reminders.status {
        case .notRequested, .authorized: return kind.purpose
        case .denied:
            return
                "Turn it on in System Settings › Privacy & Security › Reminders. Local tasks, Org, Seeds and Plot still work."
        case .restricted:
            return "Access to Reminders is restricted on this Mac. Local tasks, Org, Seeds and Plot still work."
        case .unavailable: return "Reminders is unavailable right now. Local tasks, Org, Seeds and Plot still work."
        }
    }
}
