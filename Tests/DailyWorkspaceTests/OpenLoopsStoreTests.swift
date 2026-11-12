import DailyCore
import XCTest

@testable import DailyWorkspace

/// A synthetic vault: Org, Seeds and Plot files plus two project hubs. No real notes.
enum LoopVaultFixture {
    static let today = LocalDay(year: 2026, month: 11, day: 12)

    static let inbox = """
        * Tasks
        ** TODO Call the bank
        SCHEDULED: <2026-11-12 Thu>
        ** NEXT Draft the proposal
        DEADLINE: <2026-11-20 Fri>
        ** DONE Old thing
        CLOSED: [2026-11-01 Sun 10:00]
        ** Plain heading
        """

    static let issues = """
        {"id":"brain-a1","title":"Index hubs","status":"in_progress","type":"task","labels":["project:x"],"updatedAt":"2026-11-12T13:07:47.073Z"}
        {"id":"brain-b2","title":"Alpha work","status":"open","type":"task","labels":["project:alpha"],"updatedAt":"2026-11-12T13:07:47.073Z"}
        {"id":"brain-c3","title":"Unlabelled","status":"open","type":"bug","labels":[],"updatedAt":"2026-11-12T13:07:47.073Z"}
        """

    static let plans = """
        {"id":"plan-1","name":"Plan for alpha","status":"draft","seed":"brain-b2","updatedAt":"2026-11-12T13:07:47.073Z"}
        """

    static let plotX = """
        {"id":"plot-1234abcd","name":"Ship hubs","status":"drafting","updated_at":"2026-11-12T13:07:47Z",
         "attachments":[{"id":"a1","ref":"brain-a1","role":"tracks","type":"seeds_issue"}]}
        """

    static let plotAlpha = """
        {"id":"plot-5678efgh","name":"Alpha notes","status":"active","updated_at":"2026-11-12T13:07:47Z",
         "attachments":[{"id":"a2","ref":"01-projects/alpha/notes/plan.md","role":"informs","type":"file"}]}
        """

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

    /// Writes every source. `org: false` leaves out the `org/` folder entirely.
    static func populate(_ root: URL, org: Bool = true) throws {
        if org {
            try write(inbox, to: root.appendingPathComponent("org/inbox.org"))
            try write("* Projects\n", to: root.appendingPathComponent("org/projects.org"))
        }
        try write(issues, to: root.appendingPathComponent(".seeds/issues.jsonl"))
        try write(plans, to: root.appendingPathComponent(".seeds/plans.jsonl"))
        try write(plotX, to: root.appendingPathComponent(".plot/plot-1234abcd.json"))
        try write(plotAlpha, to: root.appendingPathComponent(".plot/plot-5678efgh.json"))
        try write(hubX, to: root.appendingPathComponent("01-projects/x/x.md"))
        try write(hubAlpha, to: root.appendingPathComponent("01-projects/alpha/alpha-hub.md"))
    }
}

/// An Org source that holds its read until the test opens it.
final class HeldOrgSource: OpenLoopSource, @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var arrived = false

    var authority: LoopAuthority { .org }
    var hasArrived: Bool { lock.withLock { arrived } }

    func readLoops(now: Date) -> SourceObservation<[OpenLoop]> {
        lock.withLock { arrived = true }
        _ = semaphore.wait(timeout: .now() + 5)
        let loop = OpenLoop(
            authority: .org, nativeID: "stale", title: "From the old vault", kind: "heading", nativeStatus: "TODO",
            isDoneInSource: false, observedAt: now)
        return SourceObservation(state: .populated, value: [loop], observedAt: now)
    }

    func open() { semaphore.signal() }

    func waitForArrival() async throws {
        for _ in 0..<400 where !hasArrived {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(hasArrived, "The held read never started")
    }
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

@MainActor
final class OpenLoopsStoreTests: XCTestCase {
    private var root: URL!
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

    private func makeStore(
        root: URL?, sources: @escaping OpenLoopSourceFactory = OpenLoopsStore.liveSources
    ) -> OpenLoopsStore {
        OpenLoopsStore(tasks: tasks, reminders: reminders, vaultRoot: root, makeSources: sources)
    }

    func testEveryAuthorityAppearsWithItsNativeStatusVerbatim() async throws {
        try LoopVaultFixture.populate(root)
        let store = makeStore(root: root)

        await store.refresh()

        XCTAssertEqual(Set(store.observations.keys), Set(OpenLoopsStore.authorities))
        XCTAssertEqual(store.observations[.org]?.state, .populated)
        XCTAssertEqual(store.observations[.reminders]?.state, .populated)
        func statuses(_ authority: LoopAuthority) -> Set<String> {
            Set(store.loops(authority: authority, includeDone: true).map(\.nativeStatus))
        }
        XCTAssertEqual(statuses(.org), ["TODO", "NEXT", "DONE"])
        XCTAssertEqual(statuses(.seeds), ["in_progress", "open", "draft"])
        XCTAssertEqual(statuses(.plot), ["drafting", "active"])
        XCTAssertEqual(statuses(.local), ["open", "completed"])
        XCTAssertEqual(statuses(.reminders), ["incomplete"])
        XCTAssertEqual(store.loops(authority: .seeds, project: "x").map(\.id), ["seeds:brain-a1"])
        XCTAssertFalse(store.isRefreshing)
    }

    func testLoopsAreNotDoneFirstThenByDateThenTitle() async throws {
        try LoopVaultFixture.populate(root)
        let store = makeStore(root: root)

        await store.refresh()

        let done = store.loops.drop { !$0.isDoneInSource }
        XCTAssertTrue(done.allSatisfy(\.isDoneInSource), "Done items come last")
        let dated = store.loops.prefix(4).map(\.title)
        XCTAssertEqual(dated, ["Call the bank", "Pay rent", "Dentist", "Draft the proposal"])
    }

    func testDueOnIncludesScheduledOrgLocalAndRemindersButNeverUndatedSeeds() async throws {
        try LoopVaultFixture.populate(root)
        let store = makeStore(root: root)

        await store.refresh()

        let due = store.dueOn(today)
        XCTAssertEqual(Set(due.map(\.title)), ["Call the bank", "Pay rent", "Dentist"])
        XCTAssertFalse(due.contains { $0.authority == .seeds || $0.authority == .plot })
        XCTAssertEqual(store.dueOn(today, includeDone: true).count, 4, "Done local task due today when asked")
        XCTAssertEqual(store.dueOn(LocalDay(year: 2026, month: 11, day: 20)).map(\.title), ["Draft the proposal"])
        XCTAssertEqual(store.overdue(before: LocalDay(year: 2026, month: 11, day: 13)).count, 3)

        let counts = store.counts(on: today)
        XCTAssertEqual(counts.dueToday, 3)
        XCTAssertEqual(counts.count(.local), 2)
        XCTAssertEqual(counts.count(.org), 2)
        XCTAssertEqual(counts.count(.seeds), 4)
        XCTAssertEqual(counts.count(.plot), 2)
        XCTAssertEqual(counts.count(.reminders), 2)
        XCTAssertEqual(counts.open, 12)
    }

    func testMissingOrgFolderIsUnavailableNotEmpty() async throws {
        try LoopVaultFixture.populate(root, org: false)
        let missing = makeStore(root: root)
        await missing.refresh()

        let emptyRoot = try makeTemporaryVault(self)
        try write("* Notes only\n", to: emptyRoot.appendingPathComponent("org/inbox.org"))
        try write("* Projects\n", to: emptyRoot.appendingPathComponent("org/projects.org"))
        let empty = makeStore(root: emptyRoot)
        await empty.refresh()

        guard case .unavailable = missing.observations[.org]?.state else {
            return XCTFail("No org/ folder must be unavailable, got \(String(describing: missing.observations[.org]))")
        }
        XCTAssertEqual(empty.observations[.org]?.state, .empty)
        XCTAssertEqual(empty.observations[.seeds]?.state, .uninitialized, "No .seeds/ is uninitialized")
        XCTAssertEqual(empty.observations[.plot]?.state, .uninitialized)
        XCTAssertEqual(missing.observations[.seeds]?.state, .populated)
    }

    func testNoVaultIsUnavailableForVaultSources() async {
        let store = makeStore(root: nil)
        await store.refresh()

        for authority in OpenLoopsStore.vaultAuthorities {
            XCTAssertEqual(store.observations[authority]?.state, .unavailable(reason: "No vault is chosen."))
        }
        XCTAssertEqual(store.observations[.local]?.state, .populated, "Local tasks do not need a vault")
    }

    func testFailedReadKeepsThePreviousValueAsStale() async throws {
        try LoopVaultFixture.populate(root)
        let store = makeStore(root: root)
        await store.refresh()
        let firstSuccess = store.observations[.org]?.lastSuccessAt

        try FileManager.default.removeItem(at: root.appendingPathComponent("org"))
        await store.refresh()

        let org = try XCTUnwrap(store.observations[.org])
        guard case .unavailable = org.state else { return XCTFail("Expected unavailable, got \(org.state)") }
        XCTAssertEqual(org.value.count, 3, "The last good rows stay, marked by the failure state")
        XCTAssertEqual(org.lastSuccessAt, firstSuccess)
    }

    func testVaultSwitchMidRefreshDiscardsTheOldVaultsResult() async throws {
        let otherRoot = try makeTemporaryVault(self)
        try LoopVaultFixture.populate(otherRoot)
        let held = HeldOrgSource()
        let oldRoot = root.standardizedFileURL
        let store = makeStore(root: root) { url in
            url.standardizedFileURL == oldRoot ? [held] : OpenLoopsStore.liveSources(url)
        }

        let staleRefresh = Task { await store.refresh() }
        try await held.waitForArrival()
        store.setVaultRoot(otherRoot)
        held.open()
        await staleRefresh.value

        XCTAssertNil(store.observations[.org], "Nothing from the old vault may populate the new one")
        XCTAssertFalse(store.loops.contains { $0.title == "From the old vault" })
        XCTAssertFalse(store.isRefreshing)

        await store.refresh()
        XCTAssertEqual(store.observations[.org]?.state, .populated)
        XCTAssertTrue(store.loops.contains { $0.title == "Call the bank" })
    }

    func testOlderRefreshIsDiscardedWhenANewerOneFinishes() async throws {
        let held = HeldOrgSource()
        let calls = CallCounter()
        let store = makeStore(root: root) { url in
            calls.next() == 1 ? [held] : OpenLoopsStore.liveSources(url)
        }

        let older = Task { await store.refresh() }
        try await held.waitForArrival()
        await store.refresh()
        held.open()
        await older.value

        guard case .unavailable = store.observations[.org]?.state else {
            return XCTFail("The newer read (no org/ folder) must stand")
        }
        XCTAssertFalse(store.loops.contains { $0.title == "From the old vault" })
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

        let org = try XCTUnwrap(store.loops.first { $0.title == "Call the bank" })
        XCTAssertEqual(org.sourceLink, .note(path: "org/inbox.org", line: 2))
        let seeds = try XCTUnwrap(store.loops.first { $0.id == "seeds:brain-a1" })
        XCTAssertEqual(seeds.sourceLink, .vaultFile(path: ".seeds/issues.jsonl", line: 1))
        let plot = try XCTUnwrap(store.loops.first { $0.authority == .plot && $0.title == "Ship hubs" })
        XCTAssertEqual(plot.sourceLink?.vaultPath, ".plot/plot-1234abcd.json")
        let local = try XCTUnwrap(store.loops.first { $0.title == "Pay rent" })
        XCTAssertEqual(store.task(for: local)?.title, "Pay rent")
        let reminder = try XCTUnwrap(store.loops.first { $0.title == "Dentist" })
        XCTAssertEqual(reminder.sourceLink, .reminder("rem-1"))
        XCTAssertEqual(store.reminder(for: reminder)?.list, "Personal")
    }
}
