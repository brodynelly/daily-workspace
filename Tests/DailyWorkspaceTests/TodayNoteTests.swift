import DailyCore
import XCTest

@testable import DailyWorkspace

/// Today's note comes from the vault's `.obsidian/daily-notes.json` and is never created in the vault root
/// unless the user chose that.
@MainActor
final class TodayNoteTests: XCTestCase {
    private static let template = """
        ---
        date: "{{date:YYYY-MM-DD}}"
        ---
        # {{date:YYYY-MM-DD-dddd}}
        [[standups/{{date:YYYY}}/{{date:MM-MMM}}/{{title}}]]

        """

    private var root: URL!

    override func setUp() async throws {
        root = try makeTemporaryVault(self)
    }

    private func writeObsidianSettings(template: String = "templates/daily-note") throws {
        try write(
            #"{"folder": "250-daily", "format": "YYYY/MM-MMM/YYYY-MM-DD-dddd", "template": "\#(template)"}"#,
            to: root.appendingPathComponent(".obsidian/daily-notes.json"))
        try write(Self.template, to: root.appendingPathComponent("templates/daily-note.md"))
    }

    private func makeModel(_ configure: (inout WorkspaceSettings) -> Void = { _ in }) -> AppModel {
        let model = AppModel(dependencies: .test(configure: configure))
        model.useVault(at: root)
        XCTAssertNotNil(model.vaultSession.vault, "\(model.vaultSession.state)")
        return model
    }

    private func today(_ format: String) throws -> String { try MomentFormat().string(format, for: Date()) }

    private var expectedPath: String {
        get throws { "250-daily/" + (try today("YYYY/MM-MMM/YYYY-MM-DD-dddd")) + ".md" }
    }

    private var expectedBody: String {
        get throws {
            let title = try today("YYYY-MM-DD-dddd")
            return """
                ---
                date: "\(try today("YYYY-MM-DD"))"
                ---
                # \(title)
                [[standups/\(try today("YYYY"))/\(try today("MM-MMM"))/\(title)]]

                """
        }
    }

    private func rootEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    func testOpenTodayCreatesTheNoteAtTheObsidianPathFromTheTemplate() throws {
        try writeObsidianSettings()
        let model = makeModel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(try expectedPath).path))

        model.openToday()

        XCTAssertNil(model.document.message)
        XCTAssertEqual(model.todayNotePath, try expectedPath)
        XCTAssertEqual(model.document.relativePath, try expectedPath)
        XCTAssertTrue(model.isTodayNoteOpen)
        XCTAssertEqual(try contents(of: root.appendingPathComponent(try expectedPath)), try expectedBody)
        XCTAssertEqual(try contents(of: root.appendingPathComponent("templates/daily-note.md")), Self.template)
        XCTAssertEqual(try rootEntries(), [".obsidian", "250-daily", "templates"])

        XCTAssertEqual(model.capture("idea", to: .note), .captured)
        XCTAssertEqual(try contents(of: root.appendingPathComponent(try expectedPath)), try expectedBody + "- idea\n")
    }

    func testCaptureCreatesTodaysNoteFromTheTemplateWithoutOpeningIt() throws {
        try writeObsidianSettings()
        let model = makeModel()

        XCTAssertEqual(model.capture("idea", to: .note), .captured)

        XCTAssertNil(model.document.relativePath)
        XCTAssertEqual(try contents(of: root.appendingPathComponent(try expectedPath)), try expectedBody + "- idea\n")
    }

    func testAnExistingNoteIsOpenedUnchanged() throws {
        try writeObsidianSettings()
        try write("written in Obsidian\n", to: root.appendingPathComponent(try expectedPath))
        let model = makeModel()

        model.openToday()

        XCTAssertEqual(model.document.text, "written in Obsidian\n")
        XCTAssertEqual(try contents(of: root.appendingPathComponent(try expectedPath)), "written in Obsidian\n")
    }

    func testAMissingTemplateFallsBackToTheDateHeader() throws {
        try writeObsidianSettings(template: "templates/missing")
        let model = makeModel()

        model.openToday()

        XCTAssertEqual(
            try contents(of: root.appendingPathComponent(try expectedPath)), "# \(LocalDay(Date()))\n\n")
    }

    func testWithoutObsidianSettingsNothingIsWrittenToTheVaultRoot() throws {
        let model = makeModel()
        let refusal = "Set where daily notes go in Settings → Vault."

        model.openToday()
        XCTAssertEqual(model.document.message, refusal)
        XCTAssertNil(model.document.relativePath)
        XCTAssertNil(model.todayNotePath)
        XCTAssertEqual(model.capture("idea", to: .note), .rejected(refusal))

        XCTAssertEqual(try rootEntries(), [], "No note may appear in the vault root")
    }

    func testCustomFolderIsUsedWhenTheVaultHasNoObsidianSettings() throws {
        let model = makeModel { $0.dailyFolder = "Journal" }

        model.openToday()

        XCTAssertEqual(model.document.relativePath, "Journal/\(try today("YYYY-MM-DD")).md")
        XCTAssertEqual(try rootEntries(), ["Journal"])
    }

    func testChoosingCustomOverridesTheObsidianSettings() throws {
        try writeObsidianSettings()
        let model = makeModel {
            $0.dailyNoteSource = .custom
            $0.dailyFolder = "Journal"
            $0.dailyFilename = "YYYY/MMMM/Do"
        }

        model.openToday()

        XCTAssertEqual(model.document.relativePath, "Journal/\(try today("YYYY/MMMM/Do")).md")
        XCTAssertEqual(model.document.text, "# \(LocalDay(Date()))\n\n", "Custom notes start with the header")
    }

    func testDailyNoteSourceIsSaved() {
        let store = InMemorySettings()
        let preferences = Preferences(store: store)
        XCTAssertEqual(preferences.dailyNoteSource, .obsidian)

        preferences.dailyNoteSource = .custom

        XCTAssertEqual(store.stored?.dailyNoteSource, .custom)
    }
}
