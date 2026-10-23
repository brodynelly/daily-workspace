import SwiftUI

struct RemindersView: View {
    @StateObject private var service = RemindersService()
    @State private var title = ""
    @State private var dueToday = false
    @State private var saving = false
    var body: some View {
        VStack {
            if service.authorized {
                HStack {
                    TextField("New Apple reminder…", text: $title).textFieldStyle(.roundedBorder)
                    Toggle("Due today", isOn: $dueToday)
                    Button("Add") {
                        saving = true
                        Task {
                            if await service.add(title, due: dueToday ? Date() : nil) { title = "" }
                            saving = false
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding()
                List(service.items) { item in
                    HStack {
                        Button { Task { await service.complete(item) } } label: { Image(systemName: "circle") }
                            .buttonStyle(.plain).accessibilityLabel("Complete \(item.title)")
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.list).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let due = item.due { Text(due, style: .date).foregroundStyle(.secondary) }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Apple Reminders", systemImage: "list.bullet.circle")
                } description: {
                    Text("View incomplete reminders, add to your default list, and mark items complete. These changes sync through your Apple accounts.")
                } actions: {
                    Button("Connect Reminders") { Task { await service.connect() } }
                }
            }
            if service.loading { ProgressView().controlSize(.small) }
            if let error = service.error { InfoBanner(text: error) }
        }
        .navigationTitle("Reminders")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await service.refresh() } } }
        .task { await service.refresh() }
    }
}
