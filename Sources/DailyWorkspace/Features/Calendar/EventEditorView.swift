import SwiftUI

/// A new event or one occurrence of an existing event, as a Luuna form: labels above fields, a footer with
/// the hint on the left and Save as the one primary on the right, and Delete as a danger action at the end.
struct EventEditorView: View {
    @EnvironmentObject private var service: CalendarService
    @Environment(\.dismiss) private var dismiss
    let event: AgendaEvent?
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var allDay = false
    @State private var calendarID = ""
    @State private var location = ""
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    private enum Field { case title, location }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && end > start && !calendarID.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(event == nil ? "New Event" : "Edit Event")
                .textRole(.sectionTitle, lineBox: false)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            LabeledField("Title") {
                TextField("", text: $title, prompt: Text("Event title").foregroundStyle(Theme.inkMuted))
                    .focused($focus, equals: .title)
                    .fieldChrome(focused: focus == .title)
            }
            LabeledField("Calendar") {
                Picker("Calendar", selection: $calendarID) {
                    ForEach(service.writableCalendars) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            Toggle("All day", isOn: $allDay)
                .toggleStyle(.checkbox)
                .textRole(.bodySmall, lineBox: false)
                .foregroundStyle(Theme.inkBody)
            HStack(alignment: .top, spacing: Space.s4) {
                LabeledField("Start") { datePicker($start) }
                LabeledField("End") { datePicker($end) }
            }
            LabeledField("Location") {
                TextField("", text: $location, prompt: Text("Optional").foregroundStyle(Theme.inkMuted))
                    .focused($focus, equals: .location)
                    .fieldChrome(focused: focus == .location)
            }
            if let error { ReasonNote(error, tone: .danger) }
            FormFooter(hint: hint) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            if event != nil { deleteRow }
        }
        .padding(Space.s6)
        .frame(width: 480)
        .background(Theme.surfaceOverlay)
        .onAppear(perform: load)
        .confirmationDialog("Delete this event occurrence?", isPresented: $confirmDelete) {
            Button("Delete Event", role: .destructive, action: delete)
        }
    }

    private func datePicker(_ date: Binding<Date>) -> some View {
        DatePicker("", selection: date, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            .datePickerStyle(.compact)
            .labelsHidden()
            .fixedSize()
    }

    /// The destructive action, last and apart from the footer.
    private var deleteRow: some View {
        HStack(spacing: Space.s4) {
            Text("Removes only this occurrence from Apple Calendar.")
                .textRole(.bodySmall, lineBox: false)
                .foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Delete…") { confirmDelete = true }
                .buttonStyle(WorkspaceButtonStyle(variant: .danger, size: .small))
        }
        .padding(.top, Space.s4)
        .overlay(alignment: .top) { Hairline() }
    }

    private var hint: String {
        if end <= start { return "The end must be after the start." }
        if event != nil { return "For repeating events, only this occurrence is changed." }
        return "Adds the event to the chosen calendar."
    }

    private func load() {
        let calendars = service.writableCalendars
        calendarID = calendars.first(where: { $0.id == event?.calendarID })?.id ?? calendars.first?.id ?? ""
        if let event {
            title = event.title
            start = event.start
            end = event.end
            allDay = event.isAllDay
            location = event.location ?? ""
        } else {
            focus = .title
        }
    }

    private func save() {
        do {
            try service.save(
                EventDraft(
                    identifier: event?.identifier, title: title, start: start, end: end,
                    isAllDay: allDay, calendarID: calendarID, location: location))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() {
        do {
            if let event { try service.deleteEvent(identifier: event.identifier) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
