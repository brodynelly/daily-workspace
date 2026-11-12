import SwiftUI

/// Calendar: one day of events as record rows, quiet day navigation, and event editing.
struct CalendarView: View {
    @EnvironmentObject private var calendar: CalendarService
    @State private var creating = false

    private var authorized: Bool { calendar.status == .authorized }
    private var showingToday: Bool { Calendar.current.isDateInToday(calendar.selectedDay) }

    var body: some View {
        Page {
            PageHeader(title: AppSection.calendar.title, description: AppSection.calendar.description) {
                Button("New Event", systemImage: "plus") { creating = true }
                    .buttonStyle(WorkspaceButtonStyle(variant: authorized ? .primary : .secondary, size: .large))
                    .disabled(!authorized)
            }
            VStack(alignment: .leading, spacing: Space.s4) {
                dayNavigation
                AgendaList()
            }
        }
        .navigationTitle(AppSection.calendar.title)
        .sheet(isPresented: $creating) { EventEditorView(event: nil) }
        .onAppear { calendar.reload() }
    }

    /// The day as a section title, with quiet previous, Today and next controls.
    private var dayNavigation: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text(calendar.selectedDay, format: .dateTime.weekday(.wide).month(.wide).day().year())
                .textRole(.sectionTitle, lineBox: false)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s1) {
                Button {
                    move(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous day")
                .help("Previous day (⌘←)")
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Today") { calendar.show(day: Date()) }
                    .disabled(showingToday)
                    .help("Go to today")

                Button {
                    move(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next day")
                .help("Next day (⌘→)")
                .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .buttonStyle(.quiet)
        }
    }

    private func move(by days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: calendar.selectedDay) {
            calendar.show(day: next)
        }
    }
}
