import XCTest

@testable import DailyCore

final class WorkspaceDirectoryTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testStandardFolderIsUnderDotConfig() {
        let directory = WorkspaceDirectory.standard(home: home)
        XCTAssertEqual(directory.url.path, home.path + "/.config/daily-workspace")
        XCTAssertEqual(directory.settingsURL.lastPathComponent, "settings.json")
        XCTAssertEqual(directory.tasksURL.lastPathComponent, "tasks.json")
        XCTAssertEqual(directory.recoveryFolder.lastPathComponent, "recovery")
    }

    func testPrepareCreatesAFolderOnlyThisUserCanRead() throws {
        let directory = WorkspaceDirectory.standard(home: home)
        try directory.prepare()
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testPrepareLeavesAnExistingFolderAlone() throws {
        let directory = WorkspaceDirectory.standard(home: home)
        try FileManager.default.createDirectory(
            at: directory.url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try directory.prepare()
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    func testAdoptCopiesTheLegacyFileAndKeepsTheOriginal() throws {
        let legacy = WorkspaceDirectory.legacyFolder(home: home).appendingPathComponent("tasks.json")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"items\":[]}".utf8).write(to: legacy)
        let destination = WorkspaceDirectory.standard(home: home).tasksURL

        XCTAssertTrue(try WorkspaceDirectory.adopt(legacyFile: legacy, as: destination))

        XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: legacy))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testAdoptNeverOverwritesAnExistingFile() throws {
        let legacy = home.appendingPathComponent("old.json")
        let destination = home.appendingPathComponent("new.json")
        try Data("old".utf8).write(to: legacy)
        try Data("new".utf8).write(to: destination)

        XCTAssertFalse(try WorkspaceDirectory.adopt(legacyFile: legacy, as: destination))

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "new")
    }

    func testAdoptWithoutALegacyFileDoesNothing() throws {
        let destination = home.appendingPathComponent("new.json")
        XCTAssertFalse(try WorkspaceDirectory.adopt(legacyFile: home.appendingPathComponent("absent"), as: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}

final class SettingsPersistenceTests: XCTestCase {
    private var folder: URL!
    private var persistence: SettingsPersistence!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString)")
        persistence = SettingsPersistence(url: folder.appendingPathComponent("settings.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testMissingFileLoadsNil() throws {
        XCTAssertNil(try persistence.load())
    }

    func testRoundTrip() throws {
        let settings = WorkspaceSettings(
            vaultBookmark: Data([1, 2, 3]), vaultPath: "/Users/me/vault", dailyFolder: "250-daily",
            dailyFilename: "YYYY-MM-DD", caretPreset: .comet, showNotePreview: true,
            openRouterModel: "some/model", recentNotes: ["a.md", "b.md"])

        try persistence.save(settings)

        XCTAssertEqual(try persistence.load(), settings)
    }

    func testHandEditedFileKeepsDefaultsForMissingKeysAndIgnoresUnknownOnes() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"dailyFolder": "250-daily", "caretPreset": "warp", "fromTheFuture": 1}"#
        try Data(json.utf8).write(to: persistence.url)

        let loaded = try XCTUnwrap(try persistence.load())

        XCTAssertEqual(loaded.dailyFolder, "250-daily")
        XCTAssertEqual(loaded.caretPreset, .glide)
        XCTAssertEqual(loaded.dailyFilename, "YYYY-MM-DD")
        XCTAssertNil(loaded.vaultBookmark)
    }

    func testCorruptFileIsMovedAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: persistence.url)

        XCTAssertNil(try persistence.load())

        XCTAssertFalse(FileManager.default.fileExists(atPath: persistence.url.path))
        let aside = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix("settings.corrupt-") }
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent(aside[0]), encoding: .utf8), "not json")
    }
}
