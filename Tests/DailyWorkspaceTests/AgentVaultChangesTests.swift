import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class AgentVaultChangesTests: XCTestCase {
    private var root: URL!
    private var settings = AgentSettings()
    private var store: VaultChangeStore!

    override func setUpWithError() throws {
        root = try makeTemporaryVault(self)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("00-inbox"), withIntermediateDirectories: true)
        try write("# Plan\n- one\n", to: root.appendingPathComponent("01-projects/plan.md"))
        let app = try makeTemporaryVault(self)
        store = VaultChangeStore(
            url: app.appendingPathComponent("changes.json"), journalURL: app.appendingPathComponent("journal.jsonl"))
        settings = AgentSettings()
    }

    private func makeChanges(editor: (any OpenNoteEditing)? = nil) -> VaultChanges {
        let root = root!
        return VaultChanges(
            store: store, vault: { NoteVault(root: root) }, editor: editor, settings: { [unowned self] in settings })
    }

    private let chat = AgentRunContext(origin: "chat", conversationID: nil)

    func testNewNotesInAnAutoApplyFolderAreWrittenAtOnce() throws {
        let changes = makeChanges()
        var wrote = 0
        changes.onWrite = { wrote += 1 }
        let outcome = try changes.propose(.create(path: "00-inbox/idea.md", text: "An idea"), summary: "", run: chat)
        XCTAssertEqual(outcome.status, .applied)
        XCTAssertEqual(try contents(of: root.appendingPathComponent("00-inbox/idea.md")), "An idea\n")
        XCTAssertEqual(wrote, 1)
        XCTAssertEqual(changes.history.first?.autoApplied, true)
        XCTAssertFalse(changes.history[0].canUndo, "a created note is never deleted by the app")
        let journal = try contents(of: store.journalURL)
        XCTAssertFalse(journal.contains("An idea"))
        XCTAssertEqual(journal.split(separator: "\n").count, 2, "proposed, then applied")
    }

    func testEditsWaitForReviewThenApplyAndUndo() throws {
        let changes = makeChanges()
        let note = root.appendingPathComponent("01-projects/plan.md")
        let outcome = try changes.propose(
            .edit(path: "01-projects/plan.md", old: "- one", new: "- one\n- two"), summary: "Add two", run: chat)
        XCTAssertEqual(outcome.status, .awaitingReview)
        XCTAssertEqual(outcome.linesAdded, 1)
        XCTAssertEqual(outcome.linesRemoved, 0)
        XCTAssertEqual(try contents(of: note), "# Plan\n- one\n", "nothing is written before review")

        let id = try XCTUnwrap(changes.pending.first?.id)
        try changes.apply(id)
        XCTAssertEqual(try contents(of: note), "# Plan\n- one\n- two\n")
        XCTAssertEqual(changes.history.first?.status, .applied)
        XCTAssertEqual(changes.history.first?.autoApplied, false)

        try changes.undo(id)
        XCTAssertEqual(try contents(of: note), "# Plan\n- one\n")
        XCTAssertEqual(changes.history.first?.status, .undone)

        let reloaded = makeChanges()
        XCTAssertEqual(reloaded.history.first?.id, id, "the history survives a restart")
    }

    func testAChangedNoteIsNeverOverwritten() throws {
        let changes = makeChanges()
        let note = root.appendingPathComponent("01-projects/plan.md")
        _ = try changes.propose(.append(path: "01-projects/plan.md", text: "- two"), summary: "", run: chat)
        let id = try XCTUnwrap(changes.pending.first?.id)
        try write("# Plan\n- edited by Brody\n", to: note)
        XCTAssertThrowsError(try changes.apply(id))
        XCTAssertEqual(try contents(of: note), "# Plan\n- edited by Brody\n")
        XCTAssertEqual(changes.history.first?.status, .failed)
    }

    func testUndoLeavesANoteAloneOnceItChangedAgain() throws {
        settings.writeApproval = .autoApplyAll
        let changes = makeChanges()
        let note = root.appendingPathComponent("01-projects/plan.md")
        _ = try changes.propose(.append(path: "01-projects/plan.md", text: "- two"), summary: "", run: chat)
        let id = try XCTUnwrap(changes.history.first?.id)
        try write("# Plan\n- one\n- two\n- three\n", to: note)
        XCTAssertThrowsError(try changes.undo(id))
        XCTAssertEqual(try contents(of: note), "# Plan\n- one\n- two\n- three\n")
    }

    func testReviewModeAndOutsideFoldersQueueEverything() throws {
        let changes = makeChanges()
        let outside = try changes.propose(
            .append(path: "01-projects/plan.md", text: "- two"), summary: "", run: chat)
        XCTAssertEqual(outside.status, .awaitingReview)

        settings.writeApproval = .review
        let inside = try changes.propose(.create(path: "00-inbox/a.md", text: "a"), summary: "", run: chat)
        XCTAssertEqual(inside.status, .awaitingReview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("00-inbox/a.md").path))
    }

    func testLinksAndRoutineEditsAlwaysWaitForReview() throws {
        settings.writeApproval = .autoApplyAll
        let changes = makeChanges()
        let link = try changes.propose(
            .create(path: "00-inbox/link.md", text: "See https://example.com"), summary: "", run: chat)
        XCTAssertEqual(link.status, .awaitingReview)
        let routine = AgentRunContext(origin: "routine: Weekly review", conversationID: nil)
        let edit = try changes.propose(
            .edit(path: "01-projects/plan.md", old: "one", new: "uno"), summary: "", run: routine)
        XCTAssertEqual(edit.status, .awaitingReview)
    }

    func testTheRunCapStopsAutomaticWrites() throws {
        settings.maxAutoWritesPerRun = 2
        let changes = makeChanges()
        let statuses = try (1...3).map { index in
            try changes.propose(.create(path: "00-inbox/\(index).md", text: "n"), summary: "", run: chat).status
        }
        XCTAssertEqual(statuses, [.applied, .applied, .awaitingReview])
        let next = AgentRunContext(origin: "chat", conversationID: nil)
        XCTAssertEqual(
            try changes.propose(.create(path: "00-inbox/4.md", text: "n"), summary: "", run: next).status, .applied)
    }

    func testASecondChangeToAWaitingNoteIsMergedIntoIt() throws {
        let changes = makeChanges()
        _ = try changes.propose(.append(path: "01-projects/plan.md", text: "- two"), summary: "Two.", run: chat)
        _ = try changes.propose(.append(path: "01-projects/plan.md", text: "- three"), summary: "Three.", run: chat)
        XCTAssertEqual(changes.pending.count, 1)
        XCTAssertEqual(changes.pending[0].after, "# Plan\n- one\n- two\n- three\n")
        XCTAssertEqual(changes.pending[0].before, "# Plan\n- one\n")
        XCTAssertEqual(changes.pending[0].summary, "Two. Three.")
    }

    func testUnsafeTargetsAreRefused() throws {
        settings.writeApproval = .autoApplyAll
        let changes = makeChanges()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("_templates"), withIntermediateDirectories: true)
        let refused = [
            "root.md", "../outside.md", "/tmp/x.md", "_templates/t.md", "00-inbox/notes.txt", "missing-folder/a.md",
            ".obsidian/a.md",
        ]
        for path in refused {
            XCTAssertThrowsError(try changes.propose(.create(path: path, text: "x"), summary: "", run: chat), path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("root.md").path))
        XCTAssertThrowsError(
            try changes.propose(.create(path: "01-projects/plan.md", text: "x"), summary: "", run: chat),
            "create never replaces an existing note")
        settings.vaultWrites = false
        XCTAssertThrowsError(
            try changes.propose(.create(path: "00-inbox/off.md", text: "x"), summary: "", run: chat))
    }

    func testEditsNeedOneExactMatchAndKeepCRLF() throws {
        settings.writeApproval = .autoApplyAll
        let note = root.appendingPathComponent("01-projects/crlf.md")
        try write("a\r\nb\r\na\r\n", to: note)
        let changes = makeChanges()
        XCTAssertThrowsError(
            try changes.propose(.edit(path: "01-projects/crlf.md", old: "a", new: "c"), summary: "", run: chat))
        XCTAssertThrowsError(
            try changes.propose(.edit(path: "01-projects/crlf.md", old: "zzz", new: "c"), summary: "", run: chat))
        _ = try changes.propose(.append(path: "01-projects/crlf.md", text: "d\ne"), summary: "", run: chat)
        XCTAssertEqual(try contents(of: note), "a\r\nb\r\na\r\nd\r\ne\r\n")
    }

    func testAChangeAppliesOnlyInTheVaultItWasProposedIn() throws {
        let other = try makeTemporaryVault(self)
        try FileManager.default.createDirectory(
            at: other.appendingPathComponent("01-projects"), withIntermediateDirectories: true)
        var selected = root!
        let changes = VaultChanges(
            store: store, vault: { NoteVault(root: selected) }, editor: nil, settings: { [unowned self] in settings })
        _ = try changes.propose(.create(path: "01-projects/new.md", text: "From A"), summary: "", run: chat)
        let id = try XCTUnwrap(changes.pending.first?.id)

        selected = other
        XCTAssertThrowsError(try changes.apply(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.appendingPathComponent("01-projects/new.md").path))
        _ = try changes.propose(.create(path: "01-projects/new.md", text: "From B"), summary: "", run: chat)
        XCTAssertEqual(changes.pending.filter { $0.path == "01-projects/new.md" }.count, 1, "B's change is its own")
    }

    func testAMergedChangeStaysInReview() throws {
        settings.writeApproval = .autoApplyAll
        let changes = makeChanges()
        let routine = AgentRunContext(origin: "routine: Tidy", conversationID: nil)
        _ = try changes.propose(.edit(path: "01-projects/plan.md", old: "one", new: "uno"), summary: "", run: routine)
        let merged = try changes.propose(.append(path: "01-projects/plan.md", text: "- two"), summary: "", run: chat)
        XCTAssertEqual(merged.status, .awaitingReview, "the routine's edit still needs a person")
        XCTAssertEqual(try contents(of: root.appendingPathComponent("01-projects/plan.md")), "# Plan\n- one\n")
    }

    func testNothingIsWrittenWhenTheJournalCannotBe() throws {
        let app = try makeTemporaryVault(self)
        let journal = app.appendingPathComponent("journal.jsonl")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        let broken = VaultChangeStore(url: app.appendingPathComponent("changes.json"), journalURL: journal)
        let root = root!
        let changes = VaultChanges(
            store: broken, vault: { NoteVault(root: root) }, editor: nil, settings: { [unowned self] in settings })
        XCTAssertThrowsError(
            try changes.propose(.create(path: "00-inbox/idea.md", text: "An idea"), summary: "", run: chat))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("00-inbox/idea.md").path))
        XCTAssertTrue(changes.changes.isEmpty)
        XCTAssertNotNil(changes.storageError)
    }

    func testAnOpenNoteWithUnsavedEditsIsLeftAlone() throws {
        let editor = FakeOpenNote(path: "01-projects/plan.md", text: "# Plan\n- one\n- typing", dirty: true)
        let changes = makeChanges(editor: editor)
        XCTAssertThrowsError(
            try changes.propose(.append(path: "01-projects/plan.md", text: "- two"), summary: "", run: chat))

        editor.dirty = false
        editor.text = "# Plan\n- one\n"
        _ = try changes.propose(.append(path: "01-projects/plan.md", text: "- two"), summary: "", run: chat)
        try changes.apply(try XCTUnwrap(changes.pending.first?.id))
        XCTAssertEqual(editor.applied, ["# Plan\n- one\n- two\n"], "the open editor applies the reviewed text")
    }
}

@MainActor
private final class FakeOpenNote: OpenNoteEditing {
    var relativePath: String?
    var text: String
    var dirty: Bool
    var applied: [String] = []

    init(path: String, text: String, dirty: Bool) {
        relativePath = path
        self.text = text
        self.dirty = dirty
    }

    var hasUnsavedEdits: Bool { dirty }

    func applyReviewed(_ reviewedText: String, expecting expected: FileSnapshot) throws {
        applied.append(reviewedText)
        text = reviewedText
    }
}
