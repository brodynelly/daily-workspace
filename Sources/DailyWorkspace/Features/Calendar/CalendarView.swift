import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var calendar: CalendarService
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
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Calendar")
        .toolbar {
            Button("New Event", systemImage: "plus") { creating = true }
                .disabled(calendar.status != .authorized)
        }
        .sheet(isPresented: $creating) { EventEditorView(event: nil) }
        .onAppear { calendar.reload() }
    }

    private func move(by days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: calendar.selectedDay) {
            calendar.show(day: next)
        }
    }
}
