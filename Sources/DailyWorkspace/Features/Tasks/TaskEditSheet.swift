import DailyCore
import SwiftUI

/// Edits one local task (`tasks.json`): title, an optional due date and an optional linked vault note, as a
/// Luuna form with Save as the one primary action.
struct TaskEditSheet: View {
    @EnvironmentObject private var tasks: TaskStore
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var title = ""
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var link = ""

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        FormSheet("Edit Task") {
            LabeledField("Title") {
                BoxedTextField("Task title", text: $title, onSubmit: save)
            }
            Toggle("Due date", isOn: $hasDue)
                .toggleStyle(.checkbox)
                .textRole(.bodySmall, lineBox: false)
                .foregroundStyle(Theme.inkBody)
            if hasDue {
                LabeledField("Due") {
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .fixedSize()
                }
            }
            LabeledField("Linked note", hint: "A vault-relative path, such as 01-projects/app/app.md. Optional.") {
                BoxedTextField("Vault-relative path", text: $link, monospaced: true)
            }
            FormFooter {
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        title = task.title
        link = task.noteLink ?? ""
        if let due = task.due, let date = due.date() {
            hasDue = true
            dueDate = date
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedLink = link.trimmingCharacters(in: .whitespaces)
        tasks.edit(
            id: task.id, title: title, due: hasDue ? LocalDay(dueDate) : nil,
            noteLink: trimmedLink.isEmpty ? nil : trimmedLink)
        dismiss()
    }
}
