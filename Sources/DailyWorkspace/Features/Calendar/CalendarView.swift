import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var calendar: CalendarService
    @State private var creating = false

    var body: some View {
        Page {
            PageHeader(title: AppSection.calendar.title, description: AppSection.calendar.description) {
                Button("New Event", systemImage: "plus") { creating = true }
                    .buttonStyle(.secondary)
                    .disabled(calendar.status != .authorized)
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button {
                        move(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous day")
                    .help("Previous day (⌘←)")
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                    Text(calendar.selectedDay, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.title2.weight(.semibold))
                        .frame(minWidth: 260, alignment: .center)

                    Button {
                        move(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Next day")
                    .help("Next day (⌘→)")
                    .keyboardShortcut(.rightArrow, modifiers: .command)

                    Spacer()
                    Button("Today") { calendar.show(day: Date()) }
                        .disabled(Calendar.current.isDateInToday(calendar.selectedDay))
                }
                AgendaList()
            }
        }
        .navigationTitle(AppSection.calendar.title)
        .sheet(isPresented: $creating) { EventEditorView(event: nil) }
        .onAppear { calendar.reload() }
    }

    private func move(by days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: calendar.selectedDay) {
            calendar.show(day: next)
        }
    }
}
