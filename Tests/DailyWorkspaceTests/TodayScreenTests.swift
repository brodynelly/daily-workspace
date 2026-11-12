import DailyCore
import XCTest

@testable import DailyWorkspace

/// Today's projections of Open Loops, its stat tiles, its note panel and its inline capture.
@MainActor
final class TodayScreenTests: XCTestCase {
    private let today = LoopVaultFixture.today

    private static let inbox = """
        * Tasks
        ** TODO Call the bank
        SCHEDULED: <2026-11-12 Thu 09:30>
        ** NEXT Send the report
        DEADLINE: <2026-11-10 Tue>
        ** DONE Renew the passport
        SCHEDULED: <2026-11-12 Thu>
        ** TODO Plan the trip
        DEADLINE: <2026-11-20 Fri>
        ** TODO Only noted
        SCHEDULED: [2026-11-12 Thu]
        ** TODO Undated heading
        """

    private func makeStore() async throws -> OpenLoopsStore {
        let root = try makeTemporaryVault(self)
        try LoopVaultFixture.populate(root)
        try write(Self.inbox, to: root.appendingPathComponent("org/inbox.org"))
        let persistence = InMemoryTaskPersistence()
        persistence.stored.add(title: "Pay rent", due: today)
        persistence.stored.add(title: "Return books", due: LocalDay(year: 2026, month: 11, day: 9))
        persistence.stored.add(title: "Someday", due: nil)
        let done = try XCTUnwrap(persistence.stored.add(title: "Filed taxes", due: today))
        persistence.stored.complete(id: done.id)
        let tasks = TaskStore(makePersistence: { persistence })
        let reminders = RemindersService(store: FakeReminderStore())
        let store = OpenLoopsStore(tasks: tasks, reminders: reminders, vaultRoot: root)
        await store.refresh()
        return store
    }

    func testDueTodayListsOverdueFirstThenOwnDatedOrgAndLocalItemsAndNeverSeedsOrPlot() async throws {
        let store = try await makeStore()

        let items = TodayDue.items(from: store, on: today)

        XCTAssertEqual(
            items.map(\.loop.title),
            ["Return books", "Send the report", "Pay rent", "Call the bank", "Filed taxes", "Renew the passport"])
        XCTAssertEqual(items.filter(\.isOverdue).map(\.loop.title), ["Return books", "Send the report"])
        XCTAssertFalse(items.contains { [.seeds, .plot].contains($0.loop.authority) })
        XCTAssertFalse(
            items.contains { ["Someday", "Undated heading", "Only noted", "Plan the trip"].contains($0.loop.title) })
        XCTAssertFalse(store.loops(authority: .seeds).isEmpty, "Seeds were read, and still not listed")
        XCTAssertEqual(items.first { $0.loop.title == "Call the bank" }?.loop.nativeStatus, "TODO")
    }

    func testDueTodayDropsUndatedAndSeedsItemsEvenWhenHandedThem() {
        let now = Date()
        let seeds = OpenLoop(
            authority: .seeds, nativeID: "brain-a1", title: "Seed", kind: "task", nativeStatus: "open",
            isDoneInSource: false, scheduled: LoopDate(year: 2026, month: 11, day: 12, raw: "2026-11-12"),
            observedAt: now)
        let undated = OpenLoop(
            authority: .org, nativeID: "x", title: "Undated", kind: "heading", nativeStatus: "TODO",
            isDoneInSource: false, observedAt: now)

        XCTAssertTrue(TodayDue.items(dueToday: [seeds, undated], overdue: [seeds], on: today).isEmpty)
    }

    func testRowsUseAttentionWhileOpenAndNeutralWhenDoneNeverSuccess() async throws {
        let store = try await makeStore()
        let tones = Dictionary(
            uniqueKeysWithValues: TodayDue.items(from: store, on: today).map {
                ($0.loop.title, TodayDue.tone(for: $0.loop))
            })

        XCTAssertEqual(tones["Pay rent"], .attention)
        XCTAssertEqual(tones["Filed taxes"], .neutral)
        XCTAssertEqual(tones["Renew the passport"], .neutral)
        XCTAssertFalse(tones.values.contains(.success))
    }

    func testStatTilesComeFromOpenLoopCounts() async throws {
        let store = try await makeStore()
        let counts = store.counts(on: today)
        let items = TodayDue.items(from: store, on: today)

        let stats = TodayDue.stats(counts: counts, events: 3)

        XCTAssertEqual(stats.map(\.term), ["Events today", "Due today", "Overdue", "Open loops"])
        XCTAssertEqual(
            stats.map(\.value), ["3", counts.dueToday.formatted(), counts.overdue.formatted(), counts.open.formatted()])
        XCTAssertEqual(counts.dueToday, items.filter { !$0.isOverdue && !$0.loop.isDoneInSource }.count)
        XCTAssertEqual(counts.overdue, items.filter(\.isOverdue).count)
        let unreadable = TodayDue.stats(counts: counts, events: nil)[0]
        XCTAssertEqual(unreadable.value, "—", "No calendar access is not an empty day")
        XCTAssertNotNil(unreadable.comparison)
    }

    func testAnUnreadableOrgIsNotedSoNothingDueNeverHidesIt() async throws {
        let root = try makeTemporaryVault(self)
        let tasks = TaskStore(makePersistence: { InMemoryTaskPersistence() })
        let store = OpenLoopsStore(
            tasks: tasks, reminders: RemindersService(store: FakeReminderStore()), vaultRoot: root)
        await store.refresh()

        let notices = TodayDue.notices(from: store)

        XCTAssertTrue(TodayDue.items(from: store, on: today).isEmpty)
        XCTAssertEqual(notices.count, 1)
        XCTAssertTrue(notices[0].hasPrefix("Org could not be read"), notices[0])
    }

    func testTodayNoteLocationRefusesWithoutAFolderAndReportsExistence() throws {
        let root = try makeTemporaryVault(self)
        let model = AppModel(dependencies: .test())
        model.useVault(at: root)
        guard case .refused(let reason) = TodayNoteLocation.current(in: model) else {
            return XCTFail("Expected a refusal without a daily-note folder")
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [], "Nothing was written")

        try write(
            #"{"folder": "daily", "format": "YYYY-MM-DD"}"#,
            to: root.appendingPathComponent(".obsidian/daily-notes.json"))
        let path = "daily/\(LocalDay(Date())).md"
        XCTAssertEqual(TodayNoteLocation.current(in: model), .resolved(path: path, exists: false))
        model.openToday(create: true)
        XCTAssertEqual(TodayNoteLocation.current(in: model), .resolved(path: path, exists: true))
    }

    func testNotePreviewIsTheFirstTwelveLines() {
        let text = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n\n"
        let preview = TodayNotePreview(text: text)
        XCTAssertEqual(preview.lines.count, 12)
        XCTAssertEqual(preview.lines.last, "line 12")
        XCTAssertTrue(preview.isTruncated)
        XCTAssertFalse(TodayNotePreview(text: "# Today\n\n- one\n\n").isTruncated)
        XCTAssertEqual(TodayNotePreview(text: "# Today\n\n- one\n\n").lines, ["# Today", "", "- one"])
    }

    func testCaptureKeepsTheDraftOnFailureAndSaysCapturedOnlyAfterASave() {
        let persistence = InMemoryTaskPersistence()
        persistence.failSaves = true
        let model = AppModel(dependencies: .test(tasks: persistence))
        var state = TodayCaptureState()
        state.draft = "Buy milk"

        XCTAssertFalse(state.apply(model.capture(state.draft, to: state.destination)))
        XCTAssertEqual(state.draft, "Buy milk")
        XCTAssertEqual(state.status, .failed("Tasks could not be saved: disk full"))

        persistence.failSaves = false
        XCTAssertTrue(state.apply(model.capture(state.draft, to: state.destination)))
        XCTAssertEqual(state.draft, "")
        XCTAssertEqual(state.status, .captured(.task))
        XCTAssertEqual(model.tasks.tasks.items.map(\.title), ["Buy milk"])

        state.edited()
        XCTAssertEqual(state.status, .captured(.task), "Clearing the field after a save keeps the confirmation")
        state.draft = "Next"
        state.edited()
        XCTAssertNil(state.status)
    }
}
