import SwiftUI

/// Events of the calendar service's selected day, or the permission prompt.
struct AgendaList: View {
    @EnvironmentObject private var calendar: CalendarService
    var compact = false

    var body: some View {
        if calendar.status == .authorized {
            if calendar.events.isEmpty {
                Text("No events.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                    ForEach(calendar.events) { EventRow(event: $0) }
                }
            }
            if let refreshed = calendar.lastRefreshed {
                Text("Updated \(refreshed, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            PermissionPrompt(kind: .calendar, status: calendar.status) { await calendar.requestAccess() }
        }
    }
}

struct EventRow: View {
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
        .sheet(isPresented: $editing) { EventEditorView(event: event) }
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
