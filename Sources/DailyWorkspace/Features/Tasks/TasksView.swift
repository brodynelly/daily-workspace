import DailyCore
import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var tasks: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newTitle = ""
    @State private var newHasDue = true
    @State private var showCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            addBar
            if let message = tasks.message { InfoBanner(text: message) }
            if let deleted = tasks.recentlyDeleted {
                HStack {
                    Text("Deleted “\(deleted.title)”")
                    Spacer()
                    Button("Undo") { tasks.undoDelete() }
                    Button("Dismiss") { tasks.dismissUndo() }.buttonStyle(.link)
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
        let today = tasks.tasks.dueToday(model.today)
        let inbox = tasks.tasks.inbox
        let upcoming = tasks.tasks.upcoming(after: model.today)
        let done = tasks.tasks.completed

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
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: tasks.tasks)
    }

    private func add() {
        tasks.add(title: newTitle, due: newHasDue ? model.today : nil)
        newTitle = ""
    }
}
