import DailyCore
import SwiftUI

struct TaskEditSheet: View {
    @EnvironmentObject private var tasks: TaskStore
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
                    tasks.edit(
                        id: task.id, title: title, due: hasDue ? LocalDay(dueDate) : nil,
                        noteLink: trimmedLink.isEmpty ? nil : trimmedLink)
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
