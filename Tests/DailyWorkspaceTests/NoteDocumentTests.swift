import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class NoteDocumentTests: XCTestCase {
    private var root: URL!
    private var noteURL: URL!
    private var recovery: FakeRecovery!
    private var document: NoteDocument!

    override func setUp() async throws {
        root = try makeTemporaryVault(self)
        noteURL = root.appendingPathComponent("note.md")
        try write("original\n", to: noteURL)
        recovery = FakeRecovery()
        document = NoteDocument(recovery: recovery, autosaveDelay: .seconds(60))
        document.attach(NoteVault(root: root))
        XCTAssertEqual(try document.open(relativePath: "note.md", createIfMissing: false, initialText: ""), .opened)
    }

    func testCleanNoteReloadsExternalEdit() throws {
        try write("changed in Obsidian\n", to: noteURL)
        document.checkExternalChange()
        XCTAssertEqual(document.text, "changed in Obsidian\n")
        XCTAssertEqual(document.saveState, .clean)
    }

    func testExternalEditWhileEditingPausesSavingWithoutOverwriting() throws {
        document.userEdited("mine\n")
        try write("theirs\n", to: noteURL)
        document.checkExternalChange()
        XCTAssertEqual(document.saveState, .conflict)

        document.saveNow()
        XCTAssertEqual(try contents(of: noteURL), "theirs\n")
        XCTAssertFalse(document.flushBeforeSwitching(), "switching notes must wait for the conflict")
    }

    func testKeepMineStashesDiskVersionThenSaves() throws {
        document.userEdited("mine\n")
        try write("theirs\n", to: noteURL)
        document.checkExternalChange()

        document.resolveConflictByKeepingMine()

        XCTAssertEqual(recovery.stashed.map(\.label), ["disk-version"])
        XCTAssertEqual(recovery.stashed.first?.text, "theirs\n")
        XCTAssertEqual(try contents(of: noteURL), "mine\n")
        XCTAssertEqual(document.saveState, .clean)
    }

    func testReloadDoesNotDiscardLocalTextWhenRecoveryFails() throws {
        document.userEdited("mine\n")
        try write("theirs\n", to: noteURL)
        document.checkExternalChange()
        recovery.fails = true

        document.resolveConflictByReloading()

        XCTAssertEqual(document.text, "mine\n")
        XCTAssertEqual(document.saveState, .conflict)
        XCTAssertEqual(try contents(of: noteURL), "theirs\n")
    }

    func testKeepMineDoesNotOverwriteDiskWhenRecoveryFails() throws {
        document.userEdited("mine\n")
        try write("theirs\n", to: noteURL)
        document.checkExternalChange()
        recovery.fails = true

        document.resolveConflictByKeepingMine()

        XCTAssertEqual(try contents(of: noteURL), "theirs\n")
        XCTAssertEqual(document.saveState, .conflict)
    }

    func testAppendThatCannotBeSavedLeavesEditorUnchanged() throws {
        try write("theirs\n", to: noteURL)

        XCTAssertFalse(document.append("- idea\n"))

        XCTAssertEqual(document.text, "original\n", "a failed capture must not linger in the editor")
        XCTAssertEqual(document.saveState, .conflict)
        XCTAssertEqual(try contents(of: noteURL), "theirs\n")
    }

    func testKeepMineDoesNotClaimSuccessWhenTheSaveFails() throws {
        document.userEdited("mine\n")
        try write("theirs\n", to: noteURL)
        document.checkExternalChange()
        // A read-only folder makes the atomic write fail after the disk version was stashed.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        addTeardownBlock { [root] in
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root!.path)
        }

        document.resolveConflictByKeepingMine()

        guard case .failed = document.saveState else { return XCTFail("expected a failed save") }
        XCTAssertTrue(
            document.message?.hasPrefix("Your version could not be saved") == true, "\(document.message ?? "")")
        XCTAssertEqual(try contents(of: noteURL), "theirs\n")
    }

    func testAutosaveWritesAfterDebounce() async throws {
        let fast = NoteDocument(recovery: recovery, autosaveDelay: .milliseconds(20))
        fast.attach(NoteVault(root: root))
        try fast.open(relativePath: "note.md", createIfMissing: false, initialText: "")

        fast.userEdited("typed\n")
        for _ in 0..<100 where fast.saveState != .clean {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(fast.saveState, .clean)
        XCTAssertEqual(try contents(of: noteURL), "typed\n")
    }
}
