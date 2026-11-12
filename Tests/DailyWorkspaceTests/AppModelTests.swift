import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!
    private var model: AppModel!
    private var todayPath: String!

    override func setUp() async throws {
        root = try makeTemporaryVault(self)
        model = AppModel(dependencies: .test { $0.dailyFolder = "Daily" })
        todayPath = try DailyNoteTemplate(folder: "Daily").relativePath(for: Date())
    }

    private func useVault() {
        model.useVault(at: root)
        XCTAssertNotNil(model.vaultSession.vault, "\(model.vaultSession.state)")
    }

    func testCaptureWithoutVaultIsRejected() {
        XCTAssertEqual(model.capture("idea", to: .note), .rejected("Choose a vault to capture notes."))
    }

    func testCaptureTaskIsDueToday() {
        XCTAssertEqual(model.capture("  Buy milk ", to: .task), .captured)
        XCTAssertEqual(model.tasks.tasks.dueToday(model.today).map(\.title), ["Buy milk"])
    }

    func testCaptureToNoteDoesNotSwitchTheOpenNote() throws {
        try write("project notes\n", to: root.appendingPathComponent("Projects/alpha.md"))
        useVault()
        model.openNote("Projects/alpha.md")

        XCTAssertEqual(model.capture("idea", to: .note), .captured)

        XCTAssertEqual(model.document.relativePath, "Projects/alpha.md")
        XCTAssertEqual(model.document.text, "project notes\n")
        let today = try contents(of: root.appendingPathComponent(todayPath))
        XCTAssertTrue(today.hasSuffix("- idea\n"), today)
    }

    func testCaptureToOpenTodayNoteAppendsInEditorAndSaves() throws {
        useVault()
        model.openToday()

        XCTAssertEqual(model.capture("idea", to: .note), .captured)

        XCTAssertTrue(model.document.text.hasSuffix("- idea\n"))
        XCTAssertEqual(model.document.saveState, .clean)
        XCTAssertEqual(try contents(of: root.appendingPathComponent(todayPath)), model.document.text)
    }

    func testTodayNoteIdentityFollowsTheOpenNote() throws {
        try write("old\n", to: root.appendingPathComponent("2020-01-01.md"))
        useVault()
        model.openToday()
        XCTAssertTrue(model.isTodayNoteOpen)

        model.openNote("2020-01-01.md")

        XCTAssertFalse(model.isTodayNoteOpen, "Today must not preview an older note as today's")
        XCTAssertEqual(model.preferences.recentNotes, ["2020-01-01.md", todayPath])
    }

    func testOpeningMissingNoteExplainsInsteadOfFailingSilently() {
        useVault()
        model.openNote("gone.md")
        XCTAssertEqual(model.document.message, "“gone.md” is no longer in the vault.")
    }
}

@MainActor
final class CaptureDurabilityTests: XCTestCase {
    func testTaskCaptureThatCannotBeSavedIsRejected() {
        let persistence = InMemoryTaskPersistence()
        persistence.failSaves = true
        let model = AppModel(dependencies: .test(tasks: persistence))

        XCTAssertEqual(model.capture("Buy milk", to: .task), .rejected("Tasks could not be saved: disk full"))
        XCTAssertTrue(model.tasks.tasks.items.isEmpty)
    }
}
