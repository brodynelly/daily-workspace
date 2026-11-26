import SwiftUI

/// Seven-day time grid with a month navigator and selected-day detail rail.
struct CalendarView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var preferences: Preferences
    @State private var creating = false

    @State private var showingMonth = false

    private static let minimumWeekWidth: CGFloat = 640
    private static let monthPopoverHeight: CGFloat = 440

    private var authorized: Bool { calendar.status == .authorized }
    private var week: DateInterval? { Calendar.current.dateInterval(of: .weekOfYear, for: calendar.selectedDay) }

    var body: some View {
        GeometryReader { geometry in
            let inlineMonth = geometry.size.width >= Self.minimumWeekWidth + Metrics.sidebarWidth
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    toolbar(inlineMonth: inlineMonth)
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
                if inlineMonth {
                    VerticalHairline()
                    CalendarMonthRail().frame(width: Metrics.sidebarWidth)
                }
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

    private func toolbar(inlineMonth: Bool) -> some View {
        HStack(spacing: Space.s3) {
            if inlineMonth {
                monthTitle
            } else {
                Button {
                    showingMonth.toggle()
                } label: {
                    HStack(spacing: Space.s2) {
                        monthTitle
                        Image(systemName: "chevron.down")
                    }
                }
                .accessibilityHint("Choose a date or see its agenda")
                .popover(isPresented: $showingMonth) {
                    CalendarMonthRail().frame(width: Metrics.sidebarWidth, height: Self.monthPopoverHeight)
                }
            }
            Spacer(minLength: 0)
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
            Button("New Event", systemImage: "plus") { creating = true }
                .buttonStyle(WorkspaceButtonStyle(variant: authorized ? .primary : .secondary, size: .large))
                .disabled(!authorized)
        }
        .buttonStyle(.quiet)
        .padding(.horizontal, Space.s5)
        .frame(height: Space.s12 + Space.s4)
    }

    private var monthTitle: some View {
        Text(calendar.selectedDay, format: .dateTime.month(.wide).year())
            .textRole(.sectionTitle, lineBox: false)
            .foregroundStyle(Theme.ink)
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
