import SwiftUI

/// The scrollable week occupies the main pane; the day strip and all-day row stay visible.
struct CalendarWeekView: View {
    let week: DateInterval
    let events: [AgendaEvent]
    let selectedDay: Date
    let select: (Date) -> Void

    private let hourHeight = Space.s12
    private let timeWidth = Space.s12 + Space.s2

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: timeWidth, height: Space.s12)
                ForEach(days, id: \.self) { day in
                    Button {
                        select(day)
                    } label: {
                        VStack(spacing: Space.s1) {
                            Text(day, format: .dateTime.weekday(.abbreviated))
                                .textRole(.caption, lineBox: false)
                            Text(day, format: .dateTime.day())
                                .textRole(.label, lineBox: false)
                        }
                        .foregroundStyle(
                            Calendar.current.isDate(day, inSameDayAs: selectedDay) ? Theme.accentText : Theme.ink
                        )
                        .frame(maxWidth: .infinity, minHeight: Space.s12)
                        .background(
                            Calendar.current.isDate(day, inSameDayAs: selectedDay) ? Theme.accentSoft : Theme.surface)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                }
            }
            Hairline()
            HStack(alignment: .top, spacing: 0) {
                Text("all day")
                    .textRole(.caption, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: timeWidth, alignment: .trailing)
                    .padding(.top, Space.s1)
                ForEach(days, id: \.self) { day in
                    let allDay = events.filter { $0.isAllDay && overlaps($0, day: day) }
                    VStack(alignment: .leading, spacing: Space.sHalf) {
                        ForEach(allDay) { event in
                            CalendarEventBlock(event: event, compact: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: Space.s6, alignment: .topLeading)
                    .overlay(alignment: .leading) { VerticalHairline() }
                }
            }
            Hairline()
            ScrollViewReader { scroll in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        timeAxis
                        ForEach(days, id: \.self) { day in
                            dayColumn(day)
                        }
                    }
                }
                .onAppear { scroll.scrollTo(5, anchor: .top) }
            }
        }
    }

    private var timeAxis: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(0..<24, id: \.self) { hour in
                Text(Calendar.current.date(from: DateComponents(hour: hour)) ?? Date(), format: .dateTime.hour())
                    .textRole(.caption, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .offset(y: CGFloat(hour) * hourHeight - Space.s2)
                    .id(hour)
            }
        }
        .frame(width: timeWidth, height: 24 * hourHeight)
        .padding(.trailing, Space.s1)
    }

    private func dayColumn(_ day: Date) -> some View {
        GeometryReader { geometry in
            let placements = CalendarWeekPlacement.place(
                events.filter { !$0.isAllDay && overlaps($0, day: day) }, on: day)
            ZStack(alignment: .topLeading) {
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: Metrics.borderWidth)
                        .offset(y: CGFloat(hour) * hourHeight)
                }
                ForEach(placements) { placement in
                    CalendarEventBlock(event: placement.event, compact: false)
                        .frame(
                            width: max(0, geometry.size.width / CGFloat(placement.lanes) - Space.sHalf),
                            height: max(Space.s5, CGFloat(placement.duration) / 60 * hourHeight), alignment: .topLeading
                        )
                        .offset(
                            x: CGFloat(placement.lane) * geometry.size.width / CGFloat(placement.lanes) + Space.sHalf,
                            y: CGFloat(placement.minute) / 60 * hourHeight)
                }
                if Calendar.current.isDateInToday(day) {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: Metrics.borderWidth)
                        .offset(
                            y: CGFloat(Calendar.current.component(.hour, from: Date())) * hourHeight
                                + CGFloat(Calendar.current.component(.minute, from: Date())) / 60 * hourHeight)
                }
            }
            .frame(width: geometry.size.width, height: 24 * hourHeight, alignment: .topLeading)
            .overlay(alignment: .leading) { VerticalHairline() }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24 * hourHeight)
    }

    private func overlaps(_ event: AgendaEvent, day: Date) -> Bool {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return false }
        return event.start < end && event.end > day
    }
}

/// A connected overlap group shares its width; events within it take the first free lane.
struct CalendarWeekPlacement: Identifiable {
    let event: AgendaEvent
    let minute: Int
    let duration: Int
    let lane: Int
    let lanes: Int
    var id: String { event.id }
    private struct Slot {
        let event: AgendaEvent
        let start: Int
        let end: Int
        let lane: Int
    }

    static func place(_ events: [AgendaEvent], on day: Date, calendar: Calendar = .current) -> [Self] {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        let sorted = events.sorted { $0.start < $1.start }
        var result: [Self] = []
        var group: [Slot] = []
        var groupEnd = 0
        var active: [(end: Int, lane: Int)] = []
        func flush() {
            let count = (group.map(\.lane).max() ?? -1) + 1
            result += group.map {
                Self(
                    event: $0.event, minute: $0.start, duration: $0.end - $0.start,
                    lane: $0.lane, lanes: count)
            }
            group.removeAll(keepingCapacity: true)
            active.removeAll(keepingCapacity: true)
        }
        for event in sorted {
            let start = max(day, event.start)
            let end = min(dayEnd, event.end)
            guard end > start else { continue }
            let startComponents = calendar.dateComponents([.hour, .minute], from: start)
            let startMinute = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
            let endComponents = calendar.dateComponents([.hour, .minute], from: end)
            let endMinute = end == dayEnd ? 24 * 60 : (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
            if startMinute >= groupEnd && !group.isEmpty { flush() }
            active.removeAll { $0.end <= startMinute }
            let used = Set(active.map(\.lane))
            var lane = 0
            while used.contains(lane) { lane += 1 }
            group.append(Slot(event: event, start: startMinute, end: endMinute, lane: lane))
            active.append((endMinute, lane))
            groupEnd = max(groupEnd, endMinute)
        }
        if !group.isEmpty { flush() }
        return result
    }
}

private struct CalendarEventBlock: View {
    let event: AgendaEvent
    let compact: Bool
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sHalf) {
            Text(event.title)
                .textRole(.caption, lineBox: false)
                .lineLimit(compact ? 1 : 2)
            if !compact {
                Text(event.start, format: .dateTime.hour().minute())
                    .textRole(.caption, lineBox: false)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity, alignment: .topLeading)
        .padding(Space.s1)
        .background(Theme.surfaceRaised)
        .overlay(alignment: .leading) { event.color.frame(width: Metrics.ruleWidth) }
        .overlay { RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Theme.border) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit Event") { editing = true }
        .onTapGesture(count: 2) { editing = true }
        .contextMenu { Button("Edit Event…") { editing = true } }
        .help("Double-click to edit")
        .sheet(isPresented: $editing) { EventEditorView(event: event) }
    }
}
