import SwiftUI

/// A read-only snapshot, independent of the Calendar screen's browsed day.
enum QuickPanelCalendarSnapshot: Equatable {
    case access(PermissionStatus)
    case agenda(events: [AgendaEvent], next: AgendaEvent?)
}

/// The caller obtains a fresh snapshot from CalendarService.todayAgenda when showing the panel.
/// Opening settings is always user-initiated; rendering never requests EventKit authorization.
struct QuickPanelCalendar: View {
    let snapshot: QuickPanelCalendarSnapshot
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch snapshot {
            case .access(let status):
                accessState(status)
            case .agenda(let events, let next):
                Text("TODAY").font(.headline)
                if events.isEmpty {
                    Text("No events today.")
                } else {
                    ForEach(events) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(time(for: event))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(event.title)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("NEXT EVENT").font(.headline)
                if let next {
                    Text(next.title)
                    Text(
                        next.isAllDay
                            ? "All day · \(next.start.formatted(date: .abbreviated, time: .omitted))"
                            : next.start.formatted(date: .abbreviated, time: .shortened)
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Text("No upcoming events in the next 7 days.")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func accessState(_ status: PermissionStatus) -> some View {
        switch status {
        case .notRequested:
            Text("Calendar access has not been requested. Connect it in Daily Workspace Settings → Permissions.")
            Button("Open Settings…", action: openSettings)
        case .denied:
            Text("Calendar access is off. Enable it in System Settings → Privacy & Security → Calendars.")
            Button("Open System Settings…") { SystemSettingsPane.calendars.open() }
        case .restricted:
            Text("Calendar access is restricted on this Mac.")
            Button("Open System Settings…") { SystemSettingsPane.calendars.open() }
        case .unavailable:
            Text("Calendar is unavailable right now.")
        case .authorized:
            Text("No calendar events available.")
        }
    }

    private func time(for event: AgendaEvent) -> String {
        guard !event.isAllDay else { return "All day" }
        return
            "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}
