import SwiftUI

/// Events of the calendar service's selected day as record rows, or the connect-style permission state.
struct AgendaList: View {
    @EnvironmentObject private var calendar: CalendarService
    var compact = false

    var body: some View {
        if calendar.status == .authorized {
            VStack(alignment: .leading, spacing: compact ? Space.s2 : Space.s3) {
                if calendar.events.isEmpty {
                    EmptyState(
                        "No events", description: "Nothing is on your calendars for this day.", boxed: !compact)
                } else {
                    RecordList(variant: .rows) {
                        ForEach(calendar.events) { EventRow(event: $0) }
                    }
                }
                if let refreshed = calendar.lastRefreshed {
                    Text("Updated \(refreshed, format: .dateTime.hour().minute())")
                        .textRole(.caption, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .monospacedDigit()
                }
            }
        } else {
            PermissionEmptyState(kind: .calendar, status: calendar.status) { await calendar.requestAccess() }
        }
    }
}

/// One event: its time in tabular numerals, the title with the location under it, and the calendar as an
/// untoned tag. Double-click, the context menu or the accessibility action edits it.
struct EventRow: View {
    let event: AgendaEvent
    @State private var editing = false

    var body: some View {
        RecordRow {
            HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                Text(timeText)
                    .textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .monospacedDigit()
                    .frame(width: Self.timeColumn, alignment: .leading)
                VStack(alignment: .leading, spacing: Space.sHalf) {
                    Text(event.title)
                        .textRole(.body, lineBox: false)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .textRole(.bodySmall, lineBox: false)
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Tag(event.calendarTitle)
            }
        }
        .accessibilityElement(children: .combine)
        .contextMenu { Button("Edit Event…") { editing = true } }
        .accessibilityAction(named: "Edit Event") { editing = true }
        .onTapGesture(count: 2) { editing = true }
        .help("Double-click to edit")
        .sheet(isPresented: $editing) { EventEditorView(event: event) }
    }

    /// Wide enough for "12:00 PM – 12:00 PM" at the small body size.
    private static let timeColumn: CGFloat = 148

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
