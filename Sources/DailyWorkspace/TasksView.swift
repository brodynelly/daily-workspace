import SwiftUI
import DailyCore

struct TaskRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: TaskItem
    var showDue = false
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                state.toggleTask(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolEffect(.bounce, value: reduceMotion ? false : task.isCompleted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Reopen \(task.title)" : "Complete \(task.title)")

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                if let due = task.due, showDue || !task.isCompleted {
                    Text(dueText(due))
                        .font(.caption)
                        .foregroundStyle(due < state.today && !task.isCompleted ? Color.orange : Color.secondary)
                }
            }
            Spacer()
            if let link = task.noteLink {
                Button {
                    state.section = .notes
                    state.openNote(relativePath: link)
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("Open linked note: \(link)")
                .accessibilityLabel("Open linked note \(link)")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…") { editing = true }
            Button("Link to Open Note") { state.linkToOpenNote(task) }
                .disabled(state.noteURL == nil)
            Divider()
            Button("Delete", role: .destructive) { confirmDelete = true }
        }
        .accessibilityAction(named: "Edit") { editing = true }
        .accessibilityAction(named: "Delete") { confirmDelete = true }
        .sheet(isPresented: $editing) { TaskEditSheet(task: task) }
        .confirmationDialog("Delete “\(task.title)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { state.deleteTask(task) }
        } message: {
            Text("You can undo right after.")
        }
    }

    private func dueText(_ due: LocalDay) -> String {
        if due == state.today { return "Due today" }
        if due < state.today { return "Overdue since \(due)" }
        return "Due \(due)"
    }
}

struct TaskEditSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var title = ""
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Task").font(.headline)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Toggle("Due date", isOn: $hasDue)
            if hasDue {
                DatePicker("Due", selection: $dueDate, displayedComponents: .date)
            }
            TextField("Linked note (vault-relative path, optional)", text: $link)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmedLink = link.trimmingCharacters(in: .whitespaces)
                    state.editTask(id: task.id, title: title, due: hasDue ? LocalDay(dueDate) : nil, noteLink: trimmedLink.isEmpty ? nil : trimmedLink)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            title = task.title
            link = task.noteLink ?? ""
            if let due = task.due, let date = due.date() {
                hasDue = true
                dueDate = date
            }
        }
    }
}

struct TasksView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newTitle = ""
    @State private var newHasDue = true
    @State private var showCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            addBar
            if let message = state.taskMessage { InfoBanner(text: message) }
            if let deleted = state.recentlyDeleted {
                HStack {
                    Text("Deleted “\(deleted.title)”")
                    Spacer()
                    Button("Undo") { state.undoDelete() }
                    Button("Dismiss") { state.dismissUndo() }.buttonStyle(.link)
                }
                .padding(10)
                .background(.quaternary)
            }
            list
        }
        .navigationTitle("Tasks")
    }

    private var addBar: some View {
        HStack {
            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Toggle("Due today", isOn: $newHasDue)
                .toggleStyle(.checkbox)
            Button("Add", action: add)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
    }

    private var list: some View {
        let today = state.tasks.dueToday(state.today)
        let inbox = state.tasks.inbox
        let upcoming = state.tasks.upcoming(after: state.today)
        let done = state.tasks.completed

        return List {
            if today.isEmpty && inbox.isEmpty && upcoming.isEmpty && done.isEmpty {
                Text("No tasks yet. Add one above.").foregroundStyle(.secondary)
            }
            if !today.isEmpty {
                Section("Today") { ForEach(today) { TaskRow(task: $0, showDue: true) } }
            }
            if !inbox.isEmpty {
                Section("Inbox") { ForEach(inbox) { TaskRow(task: $0) } }
            }
            if !upcoming.isEmpty {
                Section("Upcoming") { ForEach(upcoming) { TaskRow(task: $0, showDue: true) } }
            }
            if !done.isEmpty {
                Section {
                    DisclosureGroup("Completed (\(done.count))", isExpanded: $showCompleted) {
                        ForEach(done) { TaskRow(task: $0) }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: state.tasks)
    }

    private func add() {
        state.addTask(title: newTitle, due: newHasDue ? state.today : nil)
        newTitle = ""
    }
}
