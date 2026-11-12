import XCTest

@testable import DailyCore

final class SeedsReaderTests: XCTestCase {
    private let issues = """
        {"id":"vault-a1","title":"First","status":"in_progress","type":"task","priority":2,"labels":["project:kotc-app","area:x"],"assignee":"agent:pi:run","createdAt":"2026-11-12T13:02:11.928Z","updatedAt":"2026-11-12T13:07:47.073Z","closeReason":"n/a","extensions":{"k":{"n":1}}}
        not json at all

        {"id":"vault-b2","title":"Closed one","status":"closed","type":"epic","priority":"high","createdAt":"2026-11-12T13:02:11Z","updatedAt":"2026-11-12T13:45:12.417Z","closedAt":"2026-11-12T23:45:12.417Z","labels":["workflow:handoff"]}
        {"title":"No id","status":"open"}
        ["an", "array"]
        {"id":"vault-a1","title":"First (edited)","status":"open","type":"task","updatedAt":"2026-11-13T00:00:00.000Z","labels":["project:kotc-app"]}
        {"id":"vault-c3","title":"No status"}
        """

    func testMissingSeedsFolderIsUninitialized() throws {
        let vault = try FixtureVault()
        let observation = SeedsReader(root: vault.root).readLoops(now: fixtureNow)
        XCTAssertEqual(observation.state, .uninitialized)
        XCTAssertNil(observation.lastSuccessAt)
    }

    func testEmptyStoreIsEmpty() throws {
        let vault = try FixtureVault()
        try vault.write(".seeds/issues.jsonl", "")
        try vault.write(".seeds/plans.jsonl", "\n")
        try vault.write(".seeds/config.yaml", "project: \"brain\"\nversion: \"1\"\n")
        let observation = SeedsReader(root: vault.root).readSnapshot(now: fixtureNow)
        XCTAssertEqual(observation.state, .empty)
        XCTAssertEqual(observation.value.configProject, "brain")
    }

    func testMissingIssuesFileIsPartialNotEmpty() throws {
        let vault = try FixtureVault()
        try vault.folder(".seeds")
        let observation = SeedsReader(root: vault.root).readSnapshot(now: fixtureNow)
        XCTAssertEqual(observation.state.issues.map(\.path), [".seeds/issues.jsonl"])
    }

    func testTolerantLinesBecomePartialWithLineNumbers() throws {
        let vault = try FixtureVault()
        try vault.write(".seeds/issues.jsonl", issues)
        let observation = SeedsReader(root: vault.root, calendar: loopCalendar).readSnapshot(now: fixtureNow)
        let reported = observation.state.issues.map { "\($0.line ?? 0) \($0.message)" }
        XCTAssertEqual(
            reported,
            [
                "2 skipped line: not valid JSON", "6 skipped line: not a JSON object",
                "5 skipped record without an id", "8 record has no status",
            ])
        XCTAssertEqual(observation.value.issues.map(\.id), ["vault-a1", "vault-b2", "vault-c3"])
    }

    func testFieldsLabelsAndUnknownFields() throws {
        let vault = try FixtureVault()
        try vault.write(".seeds/issues.jsonl", issues)
        let snapshot = SeedsReader(root: vault.root, calendar: loopCalendar).readSnapshot(now: fixtureNow).value
        let edited = snapshot.issues[0]
        XCTAssertEqual(edited.title, "First (edited)", "the last line for an id wins, as in Seeds")
        XCTAssertEqual(edited.line, 7)
        XCTAssertEqual(edited.project, "kotc-app")
        let closed = snapshot.issues[1]
        XCTAssertNil(closed.priority)
        XCTAssertEqual(closed.extra["priority"], .string("high"), "a mistyped field is preserved, not dropped")
        XCTAssertNil(closed.project)
        XCTAssertEqual(closed.closedAt?.localDay, LocalDay(year: 2026, month: 11, day: 12))
        XCTAssertEqual(closed.closedAt?.raw, "2026-11-12T23:45:12.417Z")
        XCTAssertNotNil(closed.createdAt, "timestamps without fractional seconds parse too")

        try vault.write(".seeds/issues.jsonl", issues.components(separatedBy: "\n")[0])
        let first = SeedsReader(root: vault.root).readSnapshot(now: fixtureNow).value.issues[0]
        XCTAssertEqual(first.priority, 2)
        XCTAssertEqual(first.assignee, "agent:pi:run")
        XCTAssertEqual(first.extra["closeReason"], .string("n/a"))
        XCTAssertEqual(first.extra["extensions"]?["k"]?["n"], .number(1))
        XCTAssertNil(first.extra["title"])
    }

    func testLoopsKeepNativeStatusAndOnlySeedsSaysDone() throws {
        let vault = try FixtureVault()
        try vault.write(".seeds/issues.jsonl", issues)
        let plan =
            #"{"id":"plan-1","seed":"vault-a1","template":"t","name":"Rollout","status":"approved","revision":1}"#
        try vault.write(".seeds/plans.jsonl", plan + "\n")
        let loops = SeedsReader(root: vault.root, calendar: loopCalendar).readLoops(now: fixtureNow).value
        XCTAssertEqual(loops.map(\.id), ["seeds:vault-a1", "seeds:vault-b2", "seeds:vault-c3", "seeds:plan-1"])
        XCTAssertEqual(loops.map(\.nativeStatus), ["open", "closed", "", "approved"])
        XCTAssertEqual(loops.map(\.isDoneInSource), [false, true, false, false])
        XCTAssertEqual(loops.map(\.kind), ["task", "epic", "issue", "plan"])
        XCTAssertEqual(loops[3].project, "kotc-app", "a plan takes its seed issue's project")
        XCTAssertEqual(loops[3].title, "Rollout")
        XCTAssertEqual(loops[0].revision, "2026-11-13T00:00:00.000Z")
        XCTAssertEqual(loops[0].sourcePath, ".seeds/issues.jsonl")
        XCTAssertEqual(loops[3].sourcePath, ".seeds/plans.jsonl")
    }
}

final class PlotReaderTests: XCTestCase {
    private let plot = """
        {
          "attachments": [
            {"added_at": "2026-11-12T13:03:40.301Z", "added_by": "agent:pi:setup", "id": "att-001",
             "ref": "vault-a1", "role": "tracks", "type": "seeds_issue"},
            {"id": "att-002", "ref": "01-projects/x/x.md", "role": "reference", "type": "file"}
          ],
          "created_at": "2026-11-12T13:02:11.987Z",
          "id": "plot-1234abcd",
          "intent": {"constraints": [], "goal": "", "non_goals": [], "success_criteria": []},
          "name": "Workspace migration",
          "schema_version": 1,
          "status": "drafting",
          "updated_at": "2026-11-12T13:45:12.188Z"
        }
        """
    private let events = """
        {"type":"plot_created","actor":"agent:pi:setup","at":"2026-11-12T13:02:11.987Z","data":{"name":"Workspace migration"}}
        {"type":"note","actor":"user:brody","at":"2026-11-12T13:03:40.354Z","data":{"text":"Scope approved."}}
        {"type":"artifact_produced","actor":"agent:pi:setup","at":"2026-11-12T13:07:47.185Z","data":{"path":"01-projects/x/x.md","text":"Verified."}}
        {"type":"note", broken
        {"type":"decision_made","actor":"user:brody","at":"2026-11-12T14:00:00Z","data":{"summary":"Ship it"}}
        """

    func testMissingFolderIsUninitializedAndEmptyFolderIsEmpty() throws {
        let vault = try FixtureVault()
        XCTAssertEqual(PlotReader(root: vault.root).readPlots(now: fixtureNow).state, .uninitialized)
        try vault.write(".plot/.index.db", "derived")
        XCTAssertEqual(PlotReader(root: vault.root).readPlots(now: fixtureNow).state, .empty)
    }

    func testPlotReferencesAndEvents() throws {
        let vault = try FixtureVault()
        try vault.write(".plot/plot-1234abcd.json", plot)
        try vault.write(".plot/plot-1234abcd.events.jsonl", events)
        let observation = PlotReader(root: vault.root).readPlots(now: fixtureNow)
        XCTAssertEqual(
            observation.state,
            .partial(issues: [
                SourceIssue(path: ".plot/plot-1234abcd.events.jsonl", line: 4, message: "skipped line: not valid JSON")
            ]))
        let record = try XCTUnwrap(observation.value.first)
        XCTAssertEqual(record.id, "plot-1234abcd")
        XCTAssertEqual(record.title, "Workspace migration")
        XCTAssertEqual(record.status, "drafting")
        XCTAssertEqual(record.goal, "")
        XCTAssertEqual(record.seedsIssueIDs, ["vault-a1"])
        XCTAssertEqual(record.notePaths, ["01-projects/x/x.md"])
        XCTAssertEqual(record.references.first?.role, "tracks")
        XCTAssertEqual(record.references.first?.addedBy, "agent:pi:setup")
        XCTAssertEqual(record.events.map(\.kind), ["plot_created", "note", "artifact_produced", "decision_made"])
        XCTAssertEqual(record.events.map(\.text), ["Workspace migration", "Scope approved.", "Verified.", "Ship it"])
        XCTAssertEqual(record.events[1].actor, "user:brody")
        XCTAssertNotNil(record.events[3].at)
        XCTAssertEqual(record.extra["schema_version"], .number(1))
        XCTAssertNotNil(record.extra["intent"])
        XCTAssertNil(record.extra["attachments"])

        let loop = record.openLoop(observedAt: fixtureNow)
        XCTAssertEqual(loop.id, "plot:plot-1234abcd")
        XCTAssertEqual(loop.nativeStatus, "drafting")
        XCTAssertFalse(loop.isDoneInSource)
        XCTAssertEqual(loop.revision, "2026-11-12T13:45:12.188Z")
    }

    func testBadPlotFileIsReportedAndOthersStillRead() throws {
        let vault = try FixtureVault()
        try vault.write(".plot/plot-1234abcd.json", plot)
        try vault.write(".plot/plot-bad00000.json", "{ nope")
        let observation = PlotReader(root: vault.root).readLoops(now: fixtureNow)
        XCTAssertEqual(observation.state.issues.map(\.path), [".plot/plot-bad00000.json"])
        XCTAssertEqual(observation.value.map(\.id), ["plot:plot-1234abcd"])
    }
}
