import SwiftUI
import DailyCore

struct TodayView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var captureAsTask = true

    private var openTasks: [TaskItem] { state.tasks.dueToday(state.today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                agenda
                tasksSection
                noteSection
                capture
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Today")
        .task(id: state.today) { state.calendarService.refresh(day: Date()) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide))
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(Date.now, format: .dateTime.month(.wide).day().year())
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var agenda: some View {
        section("Agenda", symbol: "calendar") {
            AgendaList(compact: true)
        }
    }

    private var tasksSection: some View {
        section("Tasks", symbol: "checklist") {
            if openTasks.isEmpty {
                Text("Nothing due today. Add one below, or plan from the Tasks page.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(openTasks) { task in
                        TaskRow(task: task, showDue: true)
                    }
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: openTasks.map(\.id))
            }
        }
    }

    private var noteSection: some View {
        section("Today's note", symbol: "doc.text") {
            switch state.vaultState {
            case .available:
                VStack(alignment: .leading, spacing: 10) {
                    if state.noteURL != nil {
                        Text(preview)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(state.noteURL == nil ? "Create Today's Note" : "Open Today's Note") {
                        state.section = .notes
                        state.openToday()
                    }
                    if let message = state.noteMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            case .notConfigured:
                VaultPrompt(text: "Choose your Obsidian vault to read and write daily notes.")
            case .needsReauthorization:
                VaultPrompt(text: "Access to the vault needs to be granted again.")
            case .unavailable(let why):
                VaultPrompt(text: why)
            }
        }
    }

    private var preview: String {
        let lines = state.noteText.split(separator: "\n", omittingEmptySubsequences: true).prefix(5)
        return lines.isEmpty ? "This note is empty." : lines.joined(separator: "\n")
    }

    private var capture: some View {
        section("Capture", symbol: "square.and.pencil") {
            HStack {
                TextField("Capture a thought…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
                Picker("Save as", selection: $captureAsTask) {
                    Text("Task").tag(true)
                    Text("Note").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .labelsHidden()
                .accessibilityLabel("Save as")
                Button("Add", action: commit)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func commit() {
        state.capture(draft, asTask: captureAsTask)
        draft = ""
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
    }
}

struct VaultPrompt: View {
    @EnvironmentObject var state: AppState
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).foregroundStyle(.secondary)
            Button("Choose Vault…") { state.chooseVault() }
        }
    }
}
