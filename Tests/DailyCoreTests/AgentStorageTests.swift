import XCTest

@testable import DailyCore

final class AgentStorageTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Line diff

    func testLineDiffKeepsCommonLinesAndMarksChanges() {
        let diff = LineDiff(before: "a\nb\nc\n", after: "a\nB\nc\nd\n")
        XCTAssertEqual(
            diff.lines,
            [.same("a"), .removed("b"), .added("B"), .same("c"), .added("d"), .same("")])
        XCTAssertEqual(diff.added, 2)
        XCTAssertEqual(diff.removed, 1)
        XCTAssertEqual(LineDiff(before: "", after: "x").lines, [.added("x")])
    }

    // MARK: Change store

    func testChangeStoreRoundTripsAndKeepsPendingWhileTrimmingHistory() throws {
        let store = VaultChangeStore(
            url: folder.appendingPathComponent("changes.json"), journalURL: folder.appendingPathComponent("j.jsonl"))
        XCTAssertEqual(try store.load(), [])
        let start = Date(timeIntervalSince1970: 1_000)
        var changes = (0..<(VaultChangeStore.historyLimit + 5)).map { index in
            VaultChange(
                kind: .append, path: "00-inbox/\(index).md", before: "a\n", after: "a\nb\n", summary: "",
                origin: "chat", conversationID: nil, createdAt: start.addingTimeInterval(Double(index)),
                status: .applied)
        }
        let pending = VaultChange(
            kind: .create, path: "00-inbox/new.md", before: nil, after: "x\n", summary: "why", origin: "chat",
            conversationID: UUID(), createdAt: start)
        changes.append(pending)
        try store.save(changes)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, VaultChangeStore.historyLimit + 1)
        XCTAssertTrue(loaded.contains(pending), "pending changes are never trimmed")
        XCTAssertFalse(loaded.contains { $0.path == "00-inbox/0.md" }, "the oldest history goes first")
    }

    func testJournalHoldsHashesNotText() throws {
        let store = VaultChangeStore(
            url: folder.appendingPathComponent("changes.json"), journalURL: folder.appendingPathComponent("j.jsonl"))
        let change = VaultChange(
            kind: .edit, path: "02-areas/x.md", before: "SECRET BEFORE", after: "SECRET AFTER", summary: "",
            origin: "chat", conversationID: nil, createdAt: Date())
        try store.record(
            VaultJournalEntry(
                at: Date(), changeID: change.id, event: .proposed, path: change.path, actor: "assistant",
                beforeHash: change.beforeHash, afterHash: change.afterHash))
        let journal = try String(contentsOf: store.journalURL, encoding: .utf8)
        XCTAssertFalse(journal.contains("SECRET"))
        XCTAssertTrue(journal.contains(change.afterHash))
        XCTAssertEqual(journal.split(separator: "\n").count, 1)
    }

    func testANewNoteCannotBeUndone() {
        var created = VaultChange(
            kind: .create, path: "00-inbox/a.md", before: nil, after: "x", summary: "", origin: "chat",
            conversationID: nil, createdAt: Date())
        created.status = .applied
        XCTAssertFalse(created.canUndo)
    }

    // MARK: Settings

    func testAgentSettingsDecodeTolerantlyAndNormalizeFolders() throws {
        let json = """
            {"writeApproval": "bogus", "maxAutoWritesPerRun": 999, "memory": "yes",
             "autoApplyFolders": ["/00-inbox/", " ../x ", ".hidden", "a//b"]}
            """
        let decoded = try JSONDecoder().decode(AgentSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.writeApproval, .autoApplyFolders)
        XCTAssertEqual(decoded.maxAutoWritesPerRun, AgentSettings.autoWriteRange.upperBound)
        XCTAssertEqual(decoded.autoApplyFolders, ["00-inbox", "a/b"])
        XCTAssertTrue(decoded.memory)
        XCTAssertTrue(decoded.isAutoApplyFolder("00-inbox/idea.md"))
        XCTAssertFalse(decoded.isAutoApplyFolder("00-inboxer/idea.md"))
        let settings = try JSONDecoder().decode(WorkspaceSettings.self, from: Data(#"{"agent":7}"#.utf8))
        XCTAssertEqual(settings.agent, AgentSettings())
    }

    // MARK: Memory

    func testMemoryCommandsWorkInsideTheFolder() throws {
        let memory = AgentMemory(root: folder.appendingPathComponent("memories"))
        XCTAssertEqual(try memory.view("/memories"), "Directory: /memories\n(empty)")
        try memory.create("/memories/prefs.md", text: "likes tea\nworks mornings")
        try memory.replace("/memories/prefs.md", old: "tea", new: "coffee")
        try memory.insert("/memories/prefs.md", line: 0, text: "# Preferences")
        XCTAssertEqual(try memory.view("/memories/prefs.md"), "1\t# Preferences\n2\tlikes coffee\n3\tworks mornings")
        XCTAssertEqual(try memory.view("/memories/prefs.md", range: 2...2), "2\tlikes coffee")
        try memory.rename("/memories/prefs.md", to: "/memories/people/brody.md")
        XCTAssertEqual(try memory.list().map(\.path), ["/memories/people/brody.md"])
        XCTAssertTrue(memory.index().contains("/memories/people/brody.md"))
        XCTAssertTrue(try memory.view("/memories").contains("/memories/people/brody.md"))
        try memory.delete("/memories/people/brody.md")
        XCTAssertEqual(try memory.list(), [])
    }

    func testMemoryRefusesEscapesAmbiguityAndOversizedFiles() throws {
        let memory = AgentMemory(root: folder.appendingPathComponent("memories"))
        for path in ["/memories/../x.md", "/etc/passwd", "/memories/.hidden.md", "/memories/a.sh", "memories/a.md"] {
            XCTAssertThrowsError(try memory.create(path, text: "x"), path)
        }
        try memory.create("/memories/a.md", text: "x x")
        XCTAssertThrowsError(try memory.replace("/memories/a.md", old: "x", new: "y"))
        XCTAssertThrowsError(
            try memory.create("/memories/big.md", text: String(repeating: "a", count: AgentMemory.maxFileBytes + 1)))
    }

    // MARK: Routines

    func testSchedulesFindTheNextRun() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        // Friday 2026-11-13 09:00 UTC.
        let friday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 9)))
        let daily = RoutineSchedule(kind: .daily, hour: 8, minute: 30)
        XCTAssertEqual(
            daily.next(after: friday, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 8, minute: 30)))
        let weekdays = RoutineSchedule(kind: .weekdays, hour: 8, minute: 30)
        XCTAssertEqual(
            weekdays.next(after: friday, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 8, minute: 30)),
            "Saturday and Sunday are skipped")
        let interval = RoutineSchedule(kind: .interval, intervalHours: 3)
        XCTAssertEqual(interval.next(after: friday, calendar: calendar), friday.addingTimeInterval(3 * 3_600))
        XCTAssertEqual(RoutineSchedule(kind: .interval, intervalHours: 0).intervalHours, 1)
    }

    func testAMissedRoutineIsDueOnceAndADisabledOneNever() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let created = Date(timeIntervalSince1970: 0)
        var routine = AgentRoutine(
            name: "Brief", prompt: "Summarize today", schedule: RoutineSchedule(kind: .interval, intervalHours: 1),
            createdAt: created)
        let later = created.addingTimeInterval(10 * 3_600)
        XCTAssertTrue(routine.isDue(at: later, calendar: calendar))
        routine.lastRunAt = later
        XCTAssertFalse(routine.isDue(at: later, calendar: calendar), "the catch-up run counts for every missed slot")
        routine.enabled = false
        XCTAssertFalse(routine.isDue(at: later.addingTimeInterval(7_200), calendar: calendar))
    }

    func testRoutineStoreRoundTrips() throws {
        let store = RoutineStore(url: folder.appendingPathComponent("routines.json"))
        XCTAssertEqual(try store.load(), [])
        let routine = AgentRoutine(
            name: "Weekly review", prompt: "Review the week", createdAt: Date(timeIntervalSince1970: 5))
        try store.save([routine])
        XCTAssertEqual(try store.load(), [routine])
        let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }
}
