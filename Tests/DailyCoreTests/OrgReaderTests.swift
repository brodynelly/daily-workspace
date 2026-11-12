import XCTest

@testable import DailyCore

final class OrgParsingTests: XCTestCase {
    private let inbox = """
        #+title: Inbox

        * Tasks
        ** DONE Validate setup
        CLOSED: [2026-09-29 Tue 04:53]
        :PROPERTIES:
        :CREATED: [2026-09-29 Tue 04:53]
        :END:
        ** TODO [#A] Repair validation :vault:maint:
        SCHEDULED: <2026-11-12 Thu 09:30 +1w> DEADLINE: <2026-11-20 Fri -2d>
        :PROPERTIES:
        :ID: 6F1D-ABC
        :Created: [2026-10-07 Wed]
        :END:
        Body with a checkbox:
        - [ ] not a loop
        ** NEXT Inventory
        *** WAITING Nested reply
        ** Plain heading
        ** TODO Inventory
        ** TODO Inventory
        ** CANCELLED Old idea
        *bold* is not a heading
        * Notes
        """

    func testDefaultKeywordsAndHeadingParts() {
        let document = OrgDocument(text: inbox, path: "org/inbox.org")
        XCTAssertEqual(document.keywords, .standard)
        let keywords = document.headings.map { $0.keyword ?? "-" }
        XCTAssertEqual(keywords, ["-", "DONE", "TODO", "NEXT", "WAITING", "-", "TODO", "TODO", "CANCELLED", "-"])
        let repair = document.headings[2]
        XCTAssertEqual(repair.level, 2)
        XCTAssertEqual(repair.priority, "A")
        XCTAssertEqual(repair.title, "Repair validation")
        XCTAssertEqual(repair.tags, ["vault", "maint"])
        XCTAssertEqual(repair.orgID, "6F1D-ABC")
        XCTAssertEqual(repair.created?.localDay, LocalDay(year: 2026, month: 10, day: 7))
        XCTAssertEqual(repair.line, 9)
        XCTAssertEqual(document.headings[4].outline, ["Tasks", "Inventory"])
    }

    func testTimestampsActiveInactiveTimesAndRepeaters() throws {
        let document = OrgDocument(text: inbox, path: "org/inbox.org")
        let repair = document.headings[2]
        let scheduled = try XCTUnwrap(repair.scheduled)
        XCTAssertEqual(scheduled.localDay, LocalDay(year: 2026, month: 11, day: 12))
        XCTAssertEqual(scheduled.hour, 9)
        XCTAssertEqual(scheduled.minute, 30)
        XCTAssertTrue(scheduled.isActive)
        XCTAssertEqual(scheduled.raw, "<2026-11-12 Thu 09:30 +1w>")
        let deadline = try XCTUnwrap(repair.deadline)
        XCTAssertEqual(deadline.localDay, LocalDay(year: 2026, month: 11, day: 20))
        XCTAssertNil(deadline.hour)
        let closed = try XCTUnwrap(document.headings[1].closed)
        XCTAssertFalse(closed.isActive)
        XCTAssertEqual(closed.hour, 4)
        XCTAssertEqual(OrgTimestamp.parse("<2026-01-05 Mon 8:00-9:00 .+2d/3d>")?.hour, 8)
        XCTAssertNil(OrgTimestamp.parse("<2026-13-05 Mon>"))
    }

    func testOnlyKeywordHeadingsBecomeLoopsWithVerbatimStatusAndStableIDs() {
        let loops = OrgDocument(text: inbox, path: "org/inbox.org").loops(observedAt: fixtureNow)
        XCTAssertEqual(loops.map(\.nativeStatus), ["DONE", "TODO", "NEXT", "WAITING", "TODO", "TODO", "CANCELLED"])
        XCTAssertEqual(loops.map(\.isDoneInSource), [true, false, false, false, false, false, true])
        XCTAssertEqual(loops[1].id, "org:6F1D-ABC")
        XCTAssertEqual(loops[0].id, "org:org/inbox.org#Validate setup")
        XCTAssertEqual(
            loops.filter { $0.title == "Inventory" }.map(\.id),
            ["org:org/inbox.org#Inventory", "org:org/inbox.org#Inventory~2", "org:org/inbox.org#Inventory~3"])
        XCTAssertFalse(loops.contains { $0.title.contains("not a loop") })
        XCTAssertEqual(loops[1].labels, ["vault", "maint"])
        XCTAssertEqual(loops[1].sourcePath, "org/inbox.org")
        XCTAssertNil(loops[1].project)
        XCTAssertTrue(loops.allSatisfy { $0.authority == .org && $0.kind == "heading" && $0.revision != nil })
    }

    func testCustomKeywordsReplaceTheDefaults() {
        let text = """
            #+TODO: TODO(t) IDEA | DONE(d!)
            #+seq_todo: REVIEW(r@/!) | SHIPPED KILLED
            #+TYP_TODO: Fred Sara
            * IDEA Something
            * NEXT Not a keyword here
            * SHIPPED Released
            * Sara Assigned
            * KILLED Dropped
            """
        let document = OrgDocument(text: text, path: "org/custom.org")
        XCTAssertEqual(document.keywords.active, ["TODO", "IDEA", "REVIEW", "Fred"])
        XCTAssertEqual(document.keywords.done, ["DONE", "SHIPPED", "KILLED", "Sara"])
        let loops = document.loops(observedAt: fixtureNow)
        XCTAssertEqual(loops.map(\.nativeStatus), ["IDEA", "SHIPPED", "Sara", "KILLED"])
        XCTAssertEqual(loops.map(\.isDoneInSource), [false, true, true, true])
        XCTAssertEqual(document.headings[1].title, "NEXT Not a keyword here")
    }

    func testRevisionChangesWithTheHeadingText() {
        let first = OrgDocument(text: "* TODO A\nbody", path: "a.org").headings[0].revision
        let second = OrgDocument(text: "* TODO A\nchanged", path: "a.org").headings[0].revision
        XCTAssertNotEqual(first, second)
    }
}

final class OrgReaderTests: XCTestCase {
    func testMissingVersusEmptyVersusPopulated() throws {
        let vault = try FixtureVault()
        let missing = OrgReader(root: vault.root).readLoops(now: fixtureNow)
        XCTAssertEqual(missing.state, .unavailable(reason: "org/inbox.org was not found"))
        XCTAssertNil(missing.lastSuccessAt)

        try vault.write("org/inbox.org", "#+title: Inbox\n* Tasks\n- [ ] checkbox\n")
        let partial = OrgReader(root: vault.root).readLoops(now: fixtureNow)
        XCTAssertEqual(
            partial.state,
            .partial(issues: [SourceIssue(path: "org/projects.org", message: "org/projects.org was not found")]))
        XCTAssertTrue(partial.value.isEmpty)

        try vault.write("org/projects.org", "* Projects\n")
        let empty = OrgReader(root: vault.root).readLoops(now: fixtureNow)
        XCTAssertEqual(empty.state, .empty)
        XCTAssertEqual(empty.lastSuccessAt, fixtureNow)

        try vault.write("org/projects.org", "* Projects\n** TODO Ship\n")
        let populated = OrgReader(root: vault.root).readLoops(now: fixtureNow)
        XCTAssertEqual(populated.state, .populated)
        XCTAssertEqual(populated.value.map(\.id), ["org:org/projects.org#Ship"])
        XCTAssertEqual(populated.value.first?.line, 2)
    }

    func testRefusesExcludedAndEscapingPaths() throws {
        let vault = try FixtureVault()
        try vault.write("04-archive/old.org", "* TODO Archived\n")
        let archived = OrgReader(root: vault.root, paths: ["04-archive/old.org"]).readLoops(now: fixtureNow)
        XCTAssertEqual(archived.state, .refused(reason: "04-archive/old.org is excluded (archive)"))
        let escaping = OrgReader(root: vault.root, paths: ["../outside.org"]).readLoops(now: fixtureNow)
        XCTAssertEqual(escaping.state, .refused(reason: "../outside.org resolves outside the vault"))
    }

    func testNonUTF8FileIsReportedNotEmpty() throws {
        let vault = try FixtureVault()
        try vault.write("org/inbox.org", "* TODO Fine\n")
        try Data([0xff, 0xfe]).write(to: vault.root.appendingPathComponent("org/projects.org"))
        let observation = OrgReader(root: vault.root).readLoops(now: fixtureNow)
        XCTAssertEqual(observation.state.issues.map(\.path), ["org/projects.org"])
        XCTAssertEqual(observation.value.count, 1)
    }
}

final class SourceObservationTests: XCTestCase {
    func testLastSuccessIsKeptAcrossFailures() {
        let earlier = Date(timeIntervalSince1970: 100)
        let good = SourceObservation(state: .populated, value: [1, 2], observedAt: earlier)
        XCTAssertEqual(good.lastSuccessAt, earlier)
        let failed = SourceObservation(state: .unauthorized, value: [Int](), observedAt: fixtureNow).following(good)
        XCTAssertEqual(failed.state, .unauthorized)
        XCTAssertEqual(failed.value, [1, 2])
        XCTAssertEqual(failed.lastSuccessAt, earlier)
        XCTAssertEqual(failed.observedAt, fixtureNow)
        let recovered = SourceObservation(state: .empty, value: [Int](), observedAt: fixtureNow).following(failed)
        XCTAssertEqual(recovered.value, [])
        XCTAssertEqual(recovered.lastSuccessAt, fixtureNow)
    }

    func testStatesAreDistinct() {
        let states: [SourceState] = [
            .unsupported, .unauthorized, .unavailable(reason: "x"), .uninitialized, .refused(reason: "x"),
            .partial(issues: []), .empty, .populated,
        ]
        XCTAssertEqual(Set(states).count, 8)
        XCTAssertEqual(states.filter(\.isReadable).count, 3)
    }
}
