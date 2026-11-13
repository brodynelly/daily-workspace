import XCTest

@testable import DailyWorkspace

@MainActor
final class CalendarServiceTests: XCTestCase {
    private let thursday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 15))!

    func testReloadKeepsTheBrowsedDay() {
        let store = FakeCalendarStore()
        let service = CalendarService(store: store)
        service.startWeekObservation()
        service.show(day: thursday)

        // What the app does when it is reactivated or the day changes.
        service.reload()
        store.onChange?()

        XCTAssertEqual(service.selectedDay, thursday)
        let thursdayStart = Calendar.current.startOfDay(for: thursday)
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: thursday)!
        XCTAssertEqual(store.fetchedRanges.count, 6)
        XCTAssertEqual(store.fetchedRanges.filter { $0.start == thursdayStart }.count, 3)
        XCTAssertEqual(store.fetchedRanges.filter { $0.start == week.start && $0.end == week.end }.count, 3)
    }

    func testWeekIncludesOtherDaysAndOvernightEventsButDeniedAccessClearsThem() {
        let store = FakeCalendarStore()
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: thursday)!
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: thursday)!
        let event = event("Friday", start: nextDay, end: nextDay.addingTimeInterval(3600))
        store.eventsByDayStart[Calendar.current.startOfDay(for: nextDay)] = [event]
        let service = CalendarService(store: store)
        service.startWeekObservation()

        service.show(day: thursday)
        XCTAssertTrue(service.events.isEmpty)
        XCTAssertEqual(service.weekEvents, [event])
        XCTAssertEqual(store.fetchedRanges.last?.start, week.start)
        XCTAssertEqual(store.fetchedRanges.last?.end, week.end)

        store.authorization = .denied
        service.reload()
        XCTAssertTrue(service.weekEvents.isEmpty)
    }

    func testOverlappingEventsGetSeparateLanesAndMidnightClipsToDay() {
        let system = Calendar.current
        let day = system.startOfDay(for: thursday)
        let nine = system.date(byAdding: .hour, value: 9, to: day)!
        let first = event("First", start: nine, end: nine.addingTimeInterval(3600))
        let second = event("Second", start: nine.addingTimeInterval(1800), end: nine.addingTimeInterval(5400))
        let overnight = event(
            "Overnight", start: day.addingTimeInterval(-1800),
            end: day.addingTimeInterval(1800))

        let slots = CalendarWeekPlacement.place([first, second, overnight], on: day)

        XCTAssertEqual(slots.map(\.minute), [0, 540, 570])
        XCTAssertEqual(slots.map(\.duration), [30, 60, 60])
        XCTAssertEqual(slots.map(\.lanes), [1, 2, 2])
        XCTAssertNotEqual(slots[1].lane, slots[2].lane)
    }

    func testInvalidDraftIsRejectedBeforeReachingTheStore() {
        let store = FakeCalendarStore()
        let service = CalendarService(store: store)
        let draft = EventDraft(
            identifier: nil, title: "Lunch", start: thursday, end: thursday, isAllDay: false, calendarID: "home",
            location: "")

        XCTAssertThrowsError(try service.save(draft))
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testDeniedAccessShowsNoEventsAndDoesNotFetch() {
        let store = FakeCalendarStore()
        store.authorization = .denied
        let service = CalendarService(store: store)

        service.show(day: thursday)

        XCTAssertEqual(service.status, .denied)
        XCTAssertTrue(service.events.isEmpty)
        XCTAssertTrue(store.fetchedRanges.isEmpty)
    }

    func testPanelAgendaUsesTodayWithoutChangingBrowsedCalendarDay() {
        let calendar = utcCalendar()
        let now = date(calendar, 2026, 11, 19, 12)
        let todayStart = calendar.startOfDay(for: now)
        let todayEvent = event(
            "Lunch", start: date(calendar, 2026, 11, 19, 13),
            end: date(calendar, 2026, 11, 19, 14))
        let browsedEvent = event(
            "Browsed day", start: date(calendar, 2026, 11, 23, 10),
            end: date(calendar, 2026, 11, 23, 11))
        let store = FakeCalendarStore()
        store.eventsByDayStart[todayStart] = [todayEvent]
        store.eventsByDayStart[Calendar.current.startOfDay(for: browsedEvent.start)] = [browsedEvent]
        let service = CalendarService(store: store)
        service.show(day: browsedEvent.start)

        let snapshot = service.todayAgenda(at: now, calendar: calendar)

        XCTAssertEqual(snapshot, .agenda(events: [todayEvent], next: todayEvent))
        XCTAssertEqual(service.selectedDay, browsedEvent.start)
        XCTAssertEqual(service.events, [browsedEvent])
        XCTAssertEqual(store.fetchedRanges.last?.start, todayStart)
        XCTAssertEqual(store.fetchedRanges.last?.end, date(calendar, 2026, 11, 20))
    }

    func testPanelAgendaSwitchesAtLocalMidnightAndKeepsOverlappingEventUpcoming() {
        let calendar = utcCalendar()
        let todayStart = date(calendar, 2026, 11, 19)
        let tomorrowStart = date(calendar, 2026, 11, 20)
        let overnight = event(
            "Overnight", start: date(calendar, 2026, 11, 19, 23),
            end: date(calendar, 2026, 11, 20, 0, 15))
        let breakfast = event(
            "Breakfast", start: date(calendar, 2026, 11, 20, 9),
            end: date(calendar, 2026, 11, 20, 10))
        let store = FakeCalendarStore()
        store.eventsByDayStart[todayStart] = [overnight]
        store.eventsByDayStart[tomorrowStart] = [overnight, breakfast]
        let service = CalendarService(store: store)

        XCTAssertEqual(
            service.todayAgenda(at: date(calendar, 2026, 11, 19, 23, 30), calendar: calendar),
            .agenda(events: [overnight], next: overnight))
        XCTAssertEqual(
            service.todayAgenda(at: date(calendar, 2026, 11, 20, 0, 5), calendar: calendar),
            .agenda(events: [overnight, breakfast], next: overnight))
        XCTAssertEqual(
            service.todayAgenda(at: date(calendar, 2026, 11, 20, 0, 15), calendar: calendar),
            .agenda(events: [overnight, breakfast], next: breakfast))
        XCTAssertEqual(store.fetchedRanges.map(\.start), [todayStart, tomorrowStart, tomorrowStart])
    }

    func testPanelNextEventPrefersOngoingTimedOverAllDayAndFindsTomorrowWhenTodayIsOver() {
        let calendar = utcCalendar()
        let today = date(calendar, 2026, 11, 19)
        let tomorrow = date(calendar, 2026, 11, 20)
        let allDay = event("Conference", start: today, end: tomorrow, allDay: true)
        let ongoing = event(
            "Standup", start: date(calendar, 2026, 11, 19, 9),
            end: date(calendar, 2026, 11, 19, 10))
        let later = event(
            "Review", start: date(calendar, 2026, 11, 19, 11),
            end: date(calendar, 2026, 11, 19, 12))
        let nextDay = event(
            "Tomorrow", start: date(calendar, 2026, 11, 20, 8),
            end: date(calendar, 2026, 11, 20, 9))
        let store = FakeCalendarStore()
        store.eventsByDayStart[today] = [allDay, later, ongoing]
        store.eventsByDayStart[tomorrow] = [nextDay]
        let service = CalendarService(store: store)

        XCTAssertEqual(
            service.todayAgenda(at: date(calendar, 2026, 11, 19, 9, 30), calendar: calendar),
            .agenda(events: [allDay, later, ongoing], next: ongoing))
        XCTAssertEqual(
            service.todayAgenda(at: date(calendar, 2026, 11, 19, 10), calendar: calendar),
            .agenda(events: [allDay, later, ongoing], next: allDay))
        XCTAssertEqual(
            service.todayAgenda(at: date(calendar, 2026, 11, 19, 23), calendar: calendar),
            .agenda(events: [allDay, later, ongoing], next: allDay))
        store.eventsByDayStart[today] = [later, ongoing]
        XCTAssertEqual(
            service.todayAgenda(at: date(calendar, 2026, 11, 19, 23), calendar: calendar),
            .agenda(events: [later, ongoing], next: nextDay))
        XCTAssertEqual(store.fetchedRanges.last?.start, tomorrow)
    }

    func testPanelUsesLocalCalendarDayAcrossDaylightSavingTransition() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = date(calendar, 2026, 3, 8, 1, 30)
        let start = calendar.startOfDay(for: now)
        let tomorrow = date(calendar, 2026, 3, 9)
        let localEvent = event(
            "After clocks move forward", start: date(calendar, 2026, 3, 8, 3, 30),
            end: date(calendar, 2026, 3, 8, 4))
        let store = FakeCalendarStore()
        store.eventsByDayStart[start] = [localEvent]
        let service = CalendarService(store: store)

        XCTAssertEqual(
            service.todayAgenda(at: now, calendar: calendar),
            .agenda(events: [localEvent], next: localEvent))
        XCTAssertEqual(store.fetchedRanges[0].start, start)
        XCTAssertEqual(store.fetchedRanges[0].end, tomorrow)
        XCTAssertEqual(tomorrow.timeIntervalSince(start), 23 * 60 * 60)
    }

    func testPanelDistinguishesAnEmptyTodayFromTheNextEventTomorrow() {
        let calendar = utcCalendar()
        let now = date(calendar, 2026, 11, 19, 15)
        let tomorrow = date(calendar, 2026, 11, 20)
        let breakfast = event(
            "Breakfast", start: date(calendar, 2026, 11, 20, 9),
            end: date(calendar, 2026, 11, 20, 10))
        let store = FakeCalendarStore()
        let service = CalendarService(store: store)

        XCTAssertEqual(service.todayAgenda(at: now, calendar: calendar), .agenda(events: [], next: nil))
        store.eventsByDayStart[tomorrow] = [breakfast]
        XCTAssertEqual(service.todayAgenda(at: now, calendar: calendar), .agenda(events: [], next: breakfast))
        XCTAssertEqual(store.fetchedRanges.last?.start, tomorrow)
    }

    func testPanelPermissionStatesNeverMasqueradeAsEmptyAgendaOrRequestAccess() {
        let store = FakeCalendarStore()
        let service = CalendarService(store: store)
        let calendar = utcCalendar()
        for permission in [PermissionStatus.notRequested, .denied, .restricted, .unavailable] {
            store.authorization = permission
            XCTAssertEqual(service.todayAgenda(at: thursday, calendar: calendar), .access(permission))
        }
        XCTAssertTrue(store.fetchedRanges.isEmpty)
        XCTAssertEqual(store.authorization, .unavailable)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, start: Date, end: Date, allDay: Bool = false) -> AgendaEvent {
        AgendaEvent(
            identifier: title, id: title, title: title, start: start, end: end,
            isAllDay: allDay, calendarID: "home", calendarTitle: "Home", color: .blue, location: nil)
    }

}

@MainActor
final class RemindersServiceTests: XCTestCase {
    func testFailedAddReportsWhyAndKeepsList() async {
        let store = FakeReminderStore()
        store.addError = ReminderError(message: "Choose a writable default list in Apple Reminders.")
        let service = RemindersService(store: store)

        let saved = await service.add("Renew passport", due: nil)

        XCTAssertFalse(saved)
        XCTAssertEqual(service.error, "Choose a writable default list in Apple Reminders.")
        XCTAssertTrue(service.items.isEmpty)
    }

    func testCompletingRefreshesTheList() async {
        let store = FakeReminderStore()
        store.reminders = [ReminderEntry(id: "r1", title: "Renew passport", list: "Inbox", due: nil)]
        let service = RemindersService(store: store)
        await service.refresh()

        await service.complete(service.items[0])

        XCTAssertTrue(service.items.isEmpty)
        XCTAssertEqual(store.fetchCount, 2)
    }

    func testNotRequestedAccessNeverFetches() async {
        let store = FakeReminderStore()
        store.authorization = .notRequested
        let service = RemindersService(store: store)

        await service.refresh()

        XCTAssertEqual(service.status, .notRequested)
        XCTAssertEqual(store.fetchCount, 0)
    }
}
