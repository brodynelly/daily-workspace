import SwiftUI

/// Today's events as record rows (time, title, calendar), or the Calendar connect state while access is not
/// allowed. Events are shown only once the calendar service holds today, never another day's agenda.
struct TodayAgendaSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        Panel("Agenda", description: updated) {
            Button("Calendar") { model.navigation.section = .calendar }
                .buttonStyle(.text)
                .accessibilityLabel("Open Calendar")
        } content: {
            if calendar.status == .authorized {
                let events = Self.events(of: calendar)
                if events.isEmpty {
                    Text("No events today.")
                        .textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.vertical, Space.s2)
                } else {
                    RecordList(variant: .rows) {
                        ForEach(events) { AgendaRecord(event: $0) }
                    }
                    .accessibilityLabel("Today's events")
                }
            } else {
                CalendarConnect(status: calendar.status) { await calendar.requestAccess() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The calendar service's events when it shows today; none while it still shows another day.
    @MainActor
    static func events(of calendar: CalendarService, now: Date = Date()) -> [AgendaEvent] {
        Calendar.current.isDate(calendar.selectedDay, inSameDayAs: now) ? calendar.events : []
    }

    private var updated: String? {
        guard calendar.status == .authorized, let refreshed = calendar.lastRefreshed else { return nil }
        return "Updated \(refreshed.formatted(date: .omitted, time: .shortened))"
    }
}

/// One event: the start and end time in tabular numerals, the title with its location, and the calendar as a tag.
private struct AgendaRecord: View {
    let event: AgendaEvent

    var body: some View {
        RecordRow(title: event.title, meta: event.location) {
            Text(verbatim: time)
                .textRole(.bodySmall, lineBox: false)
                .foregroundStyle(Theme.inkBody)
                .monospacedDigit()
                .frame(width: 150, alignment: .leading)
        } trailing: {
            Tag(event.calendarTitle)
        }
        .accessibilityElement(children: .combine)
    }

    private var time: String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start)–\(end)"
    }
}

/// Calendar access as a connect-style empty state: what access gives, then the one control that grants it.
private struct CalendarConnect: View {
    let status: PermissionStatus
    let request: () async -> Void

    var body: some View {
        EmptyState(title, description: description, systemImage: "calendar") {
            switch status {
            case .notRequested:
                Button("Allow Calendar Access…") { Task { await request() } }.buttonStyle(.primary)
            case .denied, .restricted:
                Button("Open System Settings") { SystemSettingsPane.calendars.open() }.buttonStyle(.primary)
            case .authorized, .unavailable:
                EmptyView()
            }
        }
    }

    private var title: String {
        switch status {
        case .notRequested: return "Calendar is not connected"
        case .denied: return "Calendar access is off"
        case .restricted: return "Calendar access is restricted"
        case .authorized, .unavailable: return "Calendar is unavailable"
        }
    }

    private var description: String {
        switch status {
        case .notRequested: return "Allow access to see today's events here. Notes and tasks work without it."
        case .denied: return "Turn on Calendar access in System Settings to see today's events here."
        case .restricted: return "Calendar access is restricted on this Mac. Notes and tasks still work."
        case .authorized, .unavailable: return "Calendar could not be read right now."
        }
    }
}
