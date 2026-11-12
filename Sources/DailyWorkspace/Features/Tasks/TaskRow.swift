import DailyCore
import SwiftUI

struct TaskRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var document: NoteDocument
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: TaskItem
    var showDue = false
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                tasks.toggle(task)
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
                        .foregroundStyle(due < model.today && !task.isCompleted ? Color.orange : Color.secondary)
                }
            }
            Spacer()
            if let link = task.noteLink {
                Button {
                    model.openNote(link)
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("Open linked note: \(link)")
                .accessibilityLabel("Open linked note \(NotePath.title(link))")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…") { editing = true }
            Button("Link to Open Note") {
                if let path = document.relativePath { tasks.link(task, toNote: path) }
            }
            .disabled(document.relativePath == nil)
            Divider()
            Button("Delete", role: .destructive) { confirmDelete = true }
        }
        .accessibilityAction(named: "Edit") { editing = true }
        .accessibilityAction(named: "Delete") { confirmDelete = true }
        .sheet(isPresented: $editing) { TaskEditSheet(task: task) }
        .confirmationDialog("Delete “\(task.title)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { tasks.delete(task) }
        } message: {
            Text("You can undo right after.")
        }
    }

    private func dueText(_ due: LocalDay) -> String {
        if due == model.today { return "Due today" }
        if due < model.today { return "Overdue since \(due)" }
        return "Due \(due)"
    }
}
