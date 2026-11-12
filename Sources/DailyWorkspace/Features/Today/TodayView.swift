import DailyCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vaultSession: VaultSession
    @EnvironmentObject private var document: NoteDocument
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var calendar: CalendarService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var destination = AppModel.CaptureDestination.task
    @State private var captureError: String?

    private var openTasks: [TaskItem] { tasks.tasks.dueToday(model.today) }

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
        .task(id: model.today) { calendar.show(day: Date()) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide))
                .font(.largeTitle.bold())
            Text(Date.now, format: .dateTime.month(.wide).day().year())
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(
                TimeZone.current.localizedName(
                    for: TimeZone.current.isDaylightSavingTime() ? .daylightSaving : .standard, locale: .current)
                    ?? TimeZone.current.identifier
            )
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
                Text("Nothing due today. Capture one below, or plan on the Tasks screen.")
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
        section("Today's Note", symbol: "doc.text") {
            if case .available = vaultSession.state {
                VStack(alignment: .leading, spacing: 10) {
                    if model.isTodayNoteOpen {
                        Text(preview)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(AppCommand.openTodayNote.title) { model.openToday(navigate: true) }
                    if let message = document.message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                VaultStatusView(state: vaultSession.state, style: .inline)
            }
        }
    }

    private var preview: String {
        let lines = document.text.split(separator: "\n", omittingEmptySubsequences: true).prefix(5)
        return lines.isEmpty ? "This note is empty." : lines.joined(separator: "\n")
    }

    private var capture: some View {
        section("Capture", symbol: "square.and.pencil") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Capture a thought…", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commit)
                    CaptureDestinationPicker(selection: $destination)
                        .frame(width: 240)
                    Button("Capture", action: commit)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let captureError {
                    Text(captureError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func commit() {
        switch model.capture(draft, to: destination) {
        case .captured:
            draft = ""
            captureError = nil
        case .rejected(let why):
            captureError = why
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
