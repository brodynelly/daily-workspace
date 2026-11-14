import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class VaultNoteReviewTests: XCTestCase {
    private var root: URL!
    private var model: AppModel!

    override func setUp() async throws {
        root = try makeTemporaryVault(self)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("00-inbox"), withIntermediateDirectories: true)
        model = AppModel(dependencies: .test())
        model.useVault(at: root)
        XCTAssertNotNil(model.vaultSession.vault)
    }

    func testQuickNotesPreviewStaysReadOnlyUntilConfirmedAndRetainsExistingSections() throws {
        let path = VaultNoteReview.quickNotesPath
        let url = root.appendingPathComponent(path)
        let original = "# Quick Notes\n\n## Capture\n\n- \n\n## Scratchpad\n"
        try write(original, to: url)

        let review = try VaultNoteReview.prepare(
            model: model, path: path, draft: "Remember this", mode: .quickNotes, requirement: .existing)
        XCTAssertEqual(review.before, original)
        XCTAssertEqual(try contents(of: url), original, "Preview must never save")
        XCTAssertTrue(review.after.contains("- Remember this\n\n## Scratchpad"))

        try review.commit(model: model)
        XCTAssertEqual(try contents(of: url), review.after)
        XCTAssertEqual(model.preferences.recentNotes.first, path)
    }

    func testQuickNotesRequiresTheExactCaptureHeadingNotSimilarText() throws {
        let path = VaultNoteReview.quickNotesPath
        let url = root.appendingPathComponent(path)
        let withoutCapture = "# Quick Notes\n\n## Capture Ideas\n\n- Hold this\n\n## Scratchpad\n"
        try write(withoutCapture, to: url)
        XCTAssertThrowsError(
            try VaultNoteReview.prepare(
                model: model, path: path, draft: "New item", mode: .quickNotes, requirement: .existing))
        XCTAssertEqual(try contents(of: url), withoutCapture)

        let withCapture =
            "# Quick Notes\n\n## Capture Ideas\n\nMention ## Capture here.\n\n"
            + "## Capture\n\n- \n\n## Scratchpad\n"
        try write(withCapture, to: url)
        let review = try VaultNoteReview.prepare(
            model: model, path: path, draft: "New item", mode: .quickNotes, requirement: .existing)
        XCTAssertTrue(review.after.contains("Mention ## Capture here.\n\n## Capture\n\n- \n- New item"))
        XCTAssertEqual(try contents(of: url), withCapture)
    }

    func testInboxNoteRequiresNewNameInExistingFolderWithoutOverwriting() throws {
        let path = "00-inbox/idea-with-sources.md"
        let url = root.appendingPathComponent(path)
        let review = try VaultNoteReview.prepare(
            model: model, path: path, draft: "# Idea\nA source.", mode: .replace, requirement: .new)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try review.commit(model: model)
        XCTAssertEqual(try contents(of: url), "# Idea\nA source.\n")
        XCTAssertThrowsError(try review.commit(model: model)) { XCTAssertEqual($0 as? VaultError, .alreadyExists) }
        XCTAssertEqual(try contents(of: url), "# Idea\nA source.\n")
    }

    func testReviewedNotePreservesMarkdownIndentationAndTrailingWhitespace() throws {
        let path = "00-inbox/indented.md"
        let draft = "    code block  \n\n"
        let review = try VaultNoteReview.prepare(
            model: model, path: path, draft: draft, mode: .replace, requirement: .new)
        XCTAssertEqual(review.after, draft)
        try review.commit(model: model)
        XCTAssertEqual(try contents(of: root.appendingPathComponent(path)), draft)
    }

    func testExternalEditAfterPreviewRefusesSaveWithoutLosingEitherVersion() throws {
        let url = root.appendingPathComponent("00-inbox/existing.md")
        try write("original\n", to: url)
        let review = try VaultNoteReview.prepare(
            model: model, path: "00-inbox/existing.md", draft: "new idea", mode: .append, requirement: .existing)
        try write("from Obsidian\n", to: url)

        XCTAssertThrowsError(try review.commit(model: model)) { XCTAssertEqual($0 as? VaultError, .conflict) }
        XCTAssertEqual(try contents(of: url), "from Obsidian\n")
        XCTAssertTrue(review.after.contains("new idea"), "The reviewed draft remains available for a new preview")
    }

    func testOpenEditorUsesItsOwnSnapshotAndRefusesUnsavedOrChangedContent() throws {
        let path = "00-inbox/open.md"
        let url = root.appendingPathComponent(path)
        try write("original\n", to: url)
        model.openNote(path)
        let review = try VaultNoteReview.prepare(
            model: model, path: path, draft: "new", mode: .append, requirement: .existing)
        model.document.userEdited("unsaved")
        XCTAssertThrowsError(try review.commit(model: model)) { XCTAssertEqual($0 as? VaultError, .conflict) }
        XCTAssertEqual(try contents(of: url), "original\n")

        model.document.saveNow()
        let next = try VaultNoteReview.prepare(
            model: model, path: path, draft: "reviewed", mode: .append, requirement: .existing)
        try next.commit(model: model)
        XCTAssertEqual(model.document.text, next.after)
        XCTAssertEqual(try contents(of: url), next.after)
    }

    func testHiddenIngestOrgAndMissingFoldersNeverCreateAnything() throws {
        let proposals = [
            "00-inbox/automation/generated.md", "00-inbox/.ingest/raw.md", "00-inbox/_index/file.md",
            "00-inbox/no-such-folder/new.md", "note.md", "../elsewhere.md", "00-inbox/action.org",
        ]
        for path in proposals {
            XCTAssertThrowsError(
                try VaultNoteReview.prepare(
                    model: model, path: path, draft: "idea", mode: .replace, requirement: .new),
                path)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("00-inbox/no-such-folder").path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("00-inbox").path), [])
        XCTAssertNotEqual(model.capture("idea", to: .quickNotes), .captured, "Direct capture cannot bypass review")
    }

    func testVaultSwitchBetweenPreviewAndSaveRefusesOldTarget() throws {
        let path = "00-inbox/old-vault.md"
        let review = try VaultNoteReview.prepare(
            model: model, path: path, draft: "only here", mode: .replace, requirement: .new)
        let second = try makeTemporaryVault(self)
        try FileManager.default.createDirectory(
            at: second.appendingPathComponent("00-inbox"), withIntermediateDirectories: true)
        model.useVault(at: second)
        XCTAssertThrowsError(try review.commit(model: model)) { XCTAssertEqual($0 as? VaultError, .conflict) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.appendingPathComponent(path).path))
    }
}
