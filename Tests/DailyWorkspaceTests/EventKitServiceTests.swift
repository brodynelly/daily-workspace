import XCTest

@testable import DailyWorkspace

@MainActor
final class CalendarServiceTests: XCTestCase {
    private let thursday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 15))!

    func testReloadKeepsTheBrowsedDay() {
        let store = FakeCalendarStore()
        let service = CalendarService(store: store)
        service.show(day: thursday)

        // What the app does when it is reactivated or the day changes.
        service.reload()
        store.onChange?()

        XCTAssertEqual(service.selectedDay, thursday)
        let thursdayStart = Calendar.current.startOfDay(for: thursday)
        XCTAssertEqual(store.fetchedRanges.map(\.start), Array(repeating: thursdayStart, count: 3))
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
