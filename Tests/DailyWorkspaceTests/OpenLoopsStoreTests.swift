import DailyCore
import XCTest

@testable import DailyWorkspace

/// A synthetic vault with two Markdown project hubs.
enum LoopVaultFixture {
    static let today = LocalDay(year: 2026, month: 11, day: 12)

    static let hubX = """
        ---
        type: project
        ---
        # Project X

        Builds the index.
        """

    static let hubAlpha = """
        ---
        type: project
        project: alpha
        ---
        # Alpha

        The alpha hub.
        """

    static func populate(_ root: URL) throws {
        try write(hubX, to: root.appendingPathComponent("01-projects/x/x.md"))
        try write(hubAlpha, to: root.appendingPathComponent("01-projects/alpha/alpha-hub.md"))
    }
}

@MainActor
final class OpenLoopsStoreTests: XCTestCase {
    var root: URL!
    private var persistence: InMemoryTaskPersistence!
    private var reminderStore: FakeReminderStore!
    private var tasks: TaskStore!
    private var reminders: RemindersService!
    private let today = LoopVaultFixture.today

    override func setUp() async throws {
        root = try makeTemporaryVault(self)
        persistence = InMemoryTaskPersistence()
        persistence.stored.add(title: "Pay rent", due: today)
        persistence.stored.add(title: "Someday", due: nil)
        let done = persistence.stored.add(title: "Filed taxes", due: today)
        persistence.stored.complete(id: try XCTUnwrap(done).id)
        reminderStore = FakeReminderStore()
        let nineThirty = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9, minute: 30)))
        reminderStore.reminders = [
            ReminderEntry(id: "rem-1", title: "Dentist", list: "Personal", due: nineThirty),
            ReminderEntry(id: "rem-2", title: "Buy stamps", list: "Errands", due: nil),
        ]
        tasks = TaskStore(makePersistence: { self.persistence })
        reminders = RemindersService(store: reminderStore)
    }

    func makeStore(
        root: URL?,
        mailEnabled: Bool = false, mail: FakeMailResponseSource? = nil,
        beforeMailRead: (@Sendable () -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) -> OpenLoopsStore {
        OpenLoopsStore(
            tasks: tasks, reminders: reminders, vaultRoot: root,
            mailEnabled: mailEnabled,
            makeMail: { MailOpenLoopReader(enabled: $0, responseSource: mail ?? FakeMailResponseSource(.unsupported)) },
            beforeMailRead: beforeMailRead, now: now)
    }

    func testEveryOpenLoopOwnerAppearsWithItsNativeStatusVerbatim() async throws {
        try LoopVaultFixture.populate(root)
        let store = makeStore(root: root)

        await store.refresh()

        XCTAssertEqual(Set(store.observations.keys), Set(OpenLoopsStore.authorities))
        XCTAssertEqual(store.observations[.reminders]?.state, .populated)
        func statuses(_ authority: LoopAuthority) -> Set<String> {
            Set(store.loops(authority: authority, includeDone: true).map(\.nativeStatus))
        }
        XCTAssertEqual(statuses(.local), ["open", "completed"])
        XCTAssertEqual(statuses(.reminders), ["incomplete"])
        XCTAssertFalse(store.isRefreshing)
    }

    func testLoopsAreNotDoneFirstThenByDateThenTitle() async throws {
        try LoopVaultFixture.populate(root)
        let store = makeStore(root: root)

        await store.refresh()

        let done = store.loops.drop { !$0.isDoneInSource }
        XCTAssertTrue(done.allSatisfy(\.isDoneInSource), "Done items come last")
        let dated = store.loops.prefix(2).map(\.title)
        XCTAssertEqual(dated, ["Pay rent", "Dentist"])
    }

    func testDueOnIncludesLocalAndReminders() async throws {
        try LoopVaultFixture.populate(root)
        let store = makeStore(root: root)

        await store.refresh()

        let due = store.dueOn(today)
        XCTAssertEqual(Set(due.map(\.title)), ["Pay rent", "Dentist"])
        XCTAssertEqual(store.dueOn(today, includeDone: true).count, 3, "Done local task due today when asked")
        XCTAssertEqual(store.overdue(before: LocalDay(year: 2026, month: 11, day: 13)).count, 2)

        let counts = store.counts(on: today)
        XCTAssertEqual(counts.dueToday, 2)
        XCTAssertEqual(counts.count(.local), 2)
        XCTAssertEqual(counts.count(.reminders), 2)
        XCTAssertEqual(counts.open, 4)
    }

    func testLocalTasksAndRemindersReDeriveWhenTheirStoresPublish() async throws {
        let store = makeStore(root: nil)
        XCTAssertEqual(store.loops(authority: .local).map(\.title), ["Pay rent", "Someday"])
        XCTAssertNil(store.observations[.reminders], "Reminders not read yet")

        tasks.add(title: "New task", due: today)
        XCTAssertTrue(store.loops(authority: .local).contains { $0.title == "New task" })

        await reminders.refresh()
        XCTAssertEqual(store.loops(authority: .reminders).count, 2)

        reminderStore.authorization = .denied
        await reminders.refresh()
        XCTAssertEqual(store.observations[.reminders]?.state, .unauthorized)
        XCTAssertEqual(persistence.saveCount, 1, "Only the explicit add saved; the store never writes")
    }

    func testSourceLinksRouteBackToTheOwner() async throws {
        try LoopVaultFixture.populate(root)
        let store = makeStore(root: root)
        await store.refresh()

        let local = try XCTUnwrap(store.loops.first { $0.title == "Pay rent" })
        XCTAssertEqual(store.task(for: local)?.title, "Pay rent")
        let reminder = try XCTUnwrap(store.loops.first { $0.title == "Dentist" })
        XCTAssertEqual(reminder.sourceLink, .reminder("rem-1"))
        XCTAssertEqual(store.reminder(for: reminder)?.list, "Personal")
    }
}
