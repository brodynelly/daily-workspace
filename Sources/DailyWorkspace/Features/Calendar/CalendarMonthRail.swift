import SwiftUI

/// Month picker and selected-day agenda; no duplicate calendar ownership or unimplemented controls.
struct CalendarMonthRail: View {
    @EnvironmentObject private var calendar: CalendarService
    @State private var displayedMonth = Date()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.sHalf), count: 7)

    private var days: [Date] {
        let system = Calendar.current
        guard let month = system.dateInterval(of: .month, for: displayedMonth),
            let week = system.dateInterval(of: .weekOfYear, for: month.start),
            let last = system.date(byAdding: .day, value: -1, to: month.end),
            let finalWeek = system.dateInterval(of: .weekOfYear, for: last)
        else { return [] }
        let count = system.dateComponents([.day], from: week.start, to: finalWeek.end).day ?? 0
        return (0..<count).compactMap { system.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .textRole(.label, lineBox: false)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    moveMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous month")
                Button {
                    moveMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next month")
            }
            .buttonStyle(.quiet)
            LazyVGrid(columns: columns, spacing: Space.s1) {
                ForEach(0..<7, id: \.self) { index in
                    let first = Calendar.current.firstWeekday
                    let weekday = ((first + index - 1) % 7) + 1
                    Text(Calendar.current.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .textRole(.caption, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                }
                ForEach(days, id: \.self) { day in
                    let selected = Calendar.current.isDate(day, inSameDayAs: calendar.selectedDay)
                    Button {
                        calendar.show(day: day)
                    } label: {
                        Text(day, format: .dateTime.day())
                            .textRole(.caption, lineBox: false)
                            .foregroundStyle(
                                selected
                                    ? Theme.accentText
                                    : Calendar.current.isDate(day, equalTo: displayedMonth, toGranularity: .month)
                                        ? Theme.ink : Theme.inkMuted
                            )
                            .frame(maxWidth: .infinity, minHeight: Metrics.controlSm)
                            .background(
                                selected ? Theme.accentSoft : Theme.surface,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                }
            }
            Hairline()
            Text(calendar.selectedDay, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .textRole(.label, lineBox: false)
                .foregroundStyle(Theme.ink)
            if calendar.status == .authorized {
                if calendar.events.isEmpty {
                    Text("No events this day")
                        .textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            ForEach(calendar.events) { event in
                                CalendarRailEventRow(event: event)
                            }
                        }
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .onAppear { displayedMonth = calendar.selectedDay }
        .onChange(of: calendar.selectedDay) { _, newDay in displayedMonth = newDay }
    }

    private func moveMonth(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = next
        }
    }
}

private struct CalendarRailEventRow: View {
    let event: AgendaEvent
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sHalf) {
            Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                .textRole(.caption, lineBox: false)
                .foregroundStyle(Theme.inkMuted)
            Text(event.title)
                .textRole(.bodySmall, lineBox: false)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(alignment: .leading) { event.color.frame(width: Metrics.ruleWidth) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit Event") { editing = true }
        .onTapGesture(count: 2) { editing = true }
        .contextMenu { Button("Edit Event…") { editing = true } }
        .sheet(isPresented: $editing) { EventEditorView(event: event) }
    }
}
