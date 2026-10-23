import SwiftUI

struct EventEditorView: View {
    @ObservedObject var service: CalendarService
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

    var body: some View {
        Form {
            Text(event == nil ? "New Event" : "Edit Event").font(.headline)
            TextField("Title", text: $title)
            Picker("Calendar", selection: $calendarID) {
                ForEach(service.writableCalendars) { Text($0.title).tag($0.id) }
            }
            Toggle("All day", isOn: $allDay)
            DatePicker("Start", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            DatePicker("End", selection: $end, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            TextField("Location", text: $location)
            if event != nil { Text("For repeating events, only this occurrence is changed.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if event != nil { Button("Delete…", role: .destructive) { confirmDelete = true } }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try service.saveEvent(identifier: event?.identifier, title: title, start: start, end: end, allDay: allDay, calendarID: calendarID, location: location)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || end <= start || calendarID.isEmpty)
            }
        }
        .padding(24).frame(width: 480)
        .onAppear {
            calendarID = service.writableCalendars.first(where: { $0.id == event?.calendarID })?.id ?? service.writableCalendars.first?.id ?? ""
            if let event { title = event.title; start = event.start; end = event.end; allDay = event.isAllDay; location = event.location ?? "" }
        }
        .confirmationDialog("Delete this event occurrence?", isPresented: $confirmDelete) {
            Button("Delete Event", role: .destructive) {
                do { if let event { try service.deleteEvent(identifier: event.identifier) }; dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
