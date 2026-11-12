import SwiftUI

struct RemindersView: View {
    @EnvironmentObject private var reminders: RemindersService
    @State private var title = ""
    @State private var dueToday = false
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            if reminders.status == .authorized {
                HStack {
                    TextField("New Apple reminder…", text: $title).textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Toggle("Due today", isOn: $dueToday).toggleStyle(.checkbox)
                    Button("Add", action: add)
                        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(14)
                if let error = reminders.error { InfoBanner(text: error) }
                List(reminders.items) { item in
                    HStack {
                        Button {
                            Task { await reminders.complete(item) }
                        } label: {
                            Image(systemName: "circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Complete \(item.title)")
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.list).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let due = item.due { Text(due, style: .date).foregroundStyle(.secondary) }
                    }
                }
                .overlay {
                    if reminders.loading {
                        ProgressView().controlSize(.small)
                    } else if reminders.hasLoaded && reminders.items.isEmpty {
                        ContentUnavailableView(
                            "No open reminders", systemImage: "checkmark.circle",
                            description: Text("Add one above, or in Apple Reminders."))
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Apple Reminders", systemImage: AppSection.reminders.symbol)
                } description: {
                    PermissionPrompt(kind: .reminders, status: reminders.status) { await reminders.requestAccess() }
                        .frame(maxWidth: 420)
                }
            }
        }
        .navigationTitle("Reminders")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await reminders.refresh() } }
                .help("Fetch changes made in Apple Reminders")
                .disabled(reminders.status != .authorized || reminders.loading)
        }
        .task { await reminders.refresh() }
    }

    private func add() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !saving else { return }
        saving = true
        Task {
            if await reminders.add(text, due: dueToday ? Date() : nil) { title = "" }
            saving = false
        }
    }
}
