import SwiftUI

/// Seven-day time grid with a month navigator and selected-day detail rail.
struct CalendarView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var preferences: Preferences
    @State private var creating = false

    private var authorized: Bool { calendar.status == .authorized }
    private var week: DateInterval? { Calendar.current.dateInterval(of: .weekOfYear, for: calendar.selectedDay) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    toolbar
                    if authorized, let week {
                        CalendarWeekView(week: week, events: calendar.weekEvents, selectedDay: calendar.selectedDay) {
                            calendar.show(day: $0)
                        }
                    } else {
                        PermissionEmptyState(kind: .calendar, status: calendar.status) {
                            await calendar.requestAccess()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VerticalHairline()
                CalendarMonthRail()
                    .frame(width: Metrics.sidebarWidth)
            }
        }
        .navigationTitle(AppSection.calendar.title)
        .sheet(isPresented: $creating) { EventEditorView(event: nil) }
        .onAppear {
            calendar.startWeekObservation()
            calendar.reload()
        }
        .onDisappear { calendar.stopWeekObservation() }
    }

    private var toolbar: some View {
        HStack(spacing: Space.s3) {
            Button("Today") { calendar.show(day: Date()) }
                .disabled(Calendar.current.isDateInToday(calendar.selectedDay))
            Button {
                move(by: -7)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous week")
            .help(shortcutHelp("Previous week", id: "calendar.previousWeek"))
            .keyboardShortcut(
                KeyboardShortcutCatalog.binding(for: "calendar.previousWeek", preferences: preferences)?.menuShortcut)
            Button {
                move(by: 7)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next week")
            .help(shortcutHelp("Next week", id: "calendar.nextWeek"))
            .keyboardShortcut(
                KeyboardShortcutCatalog.binding(for: "calendar.nextWeek", preferences: preferences)?.menuShortcut)
            Text(calendar.selectedDay, format: .dateTime.month(.wide).year())
                .textRole(.sectionTitle, lineBox: false)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("New Event", systemImage: "plus") { creating = true }
                .buttonStyle(WorkspaceButtonStyle(variant: authorized ? .primary : .secondary, size: .large))
                .disabled(!authorized)
        }
        .buttonStyle(.quiet)
        .padding(.horizontal, Space.s5)
        .frame(height: Space.s12 + Space.s4)
    }

    private func shortcutHelp(_ title: String, id: String) -> String {
        guard let binding = KeyboardShortcutCatalog.binding(for: id, preferences: preferences) else { return title }
        return "\(title) (\(KeyboardShortcutCatalog.label(for: binding)))"
    }

    private func move(by days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: calendar.selectedDay) {
            calendar.show(day: next)
        }
    }
}
