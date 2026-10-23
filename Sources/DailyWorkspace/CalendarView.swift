import SwiftUI
import AppKit

struct AgendaList: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var service: CalendarService
    var compact = false

    var body: some View {
        switch service.status {
        case .notRequested:
            VStack(alignment: .leading, spacing: 8) {
                Text("See today's events here, and add or edit events without leaving the app.")
                    .foregroundStyle(.secondary)
                Button("Enable Calendar…") { Task { await service.requestAccess() } }
            }
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 8) {
                Text(service.status == .restricted
                     ? "Calendar access is restricted on this Mac. Notes and tasks still work."
                     : "Calendar access is off. Notes and tasks still work.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .unavailable:
            Text("Calendar is unavailable right now.").foregroundStyle(.secondary)
        case .authorized:
            if service.events.isEmpty {
                Text("No events.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                    ForEach(service.events) { EventRow(event: $0) }
                }
            }
            if let refreshed = service.lastRefreshed {
                Text("Updated \(refreshed, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct EventRow: View {
    @EnvironmentObject var state: AppState
    let event: AgendaEvent
    @State private var editing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).fontWeight(.medium)
                Text(timeText).font(.caption).foregroundStyle(.secondary)
                Text(event.calendarTitle + (event.location.map { " · \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .contextMenu { Button("Edit Event…") { editing = true } }
        .accessibilityAction(named: "Edit Event") { editing = true }
        .onTapGesture(count: 2) { editing = true }
        .sheet(isPresented: $editing) { EventEditorView(service: state.calendarService, event: event) }
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

struct CalendarView: View {
    @EnvironmentObject var state: AppState
    @State private var day = Date()
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button {
                        move(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous day")
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                    Text(day, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.title2.weight(.semibold))
                        .frame(minWidth: 260, alignment: .center)

                    Button {
                        move(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Next day")
                    .keyboardShortcut(.rightArrow, modifiers: .command)

                    Spacer()
                    Button("Today") { day = Date() }
                        .disabled(Calendar.current.isDateInToday(day))
                }
                AgendaList(service: state.calendarService)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Calendar")
        .toolbar {
            Button("New Event", systemImage: "plus") { creating = true }
                .disabled(state.calendarService.status != .authorized)
        }
        .sheet(isPresented: $creating) { EventEditorView(service: state.calendarService, event: nil) }
        .task(id: day) { state.calendarService.refresh(day: day) }
    }

    private func move(by days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: day) { day = next }
    }
}
