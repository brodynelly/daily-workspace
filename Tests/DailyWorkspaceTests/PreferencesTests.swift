import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class PreferencesTests: XCTestCase {
    private func makeLegacyDefaults() -> UserDefaults {
        let suite = "DailyWorkspaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testEveryChangeIsSaved() {
        let store = InMemorySettings()
        let preferences = Preferences(store: store)

        preferences.dailyFolder = "250-daily"
        preferences.caretPreset = .comet
        preferences.rememberRecent("a.md")

        XCTAssertEqual(store.stored?.dailyFolder, "250-daily")
        XCTAssertEqual(store.stored?.caretPreset, .comet)
        XCTAssertEqual(store.stored?.recentNotes, ["a.md"])
    }

    func testSavedSettingsAreLoaded() {
        let store = InMemorySettings()
        store.stored = WorkspaceSettings(dailyFolder: "250-daily", showNotePreview: true)

        let preferences = Preferences(store: store)

        XCTAssertEqual(preferences.dailyFolder, "250-daily")
        XCTAssertTrue(preferences.showNotePreview)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testLegacyDefaultsAreImportedAndSavedOnFirstLaunch() {
        let defaults = makeLegacyDefaults()
        defaults.set("Daily", forKey: Preferences.LegacyKey.dailyFolder)
        defaults.set(["x.md"], forKey: Preferences.LegacyKey.recentNotes)
        defaults.set(Data([7]), forKey: Preferences.LegacyKey.vaultBookmark)
        let store = InMemorySettings()

        let preferences = Preferences(store: store, legacyDefaults: defaults)

        XCTAssertEqual(preferences.dailyFolder, "Daily")
        XCTAssertEqual(preferences.vaultBookmark, Data([7]))
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.stored?.recentNotes, ["x.md"])
    }

    func testLegacyDefaultsAreIgnoredOnceASettingsFileExists() {
        let defaults = makeLegacyDefaults()
        defaults.set("Old", forKey: Preferences.LegacyKey.dailyFolder)
        let store = InMemorySettings()
        store.stored = WorkspaceSettings(dailyFolder: "250-daily")

        let preferences = Preferences(store: store, legacyDefaults: defaults)

        XCTAssertEqual(preferences.dailyFolder, "250-daily")
        XCTAssertEqual(store.saveCount, 0)
    }

    func testUnreadableSettingsAreNeverOverwritten() {
        let store = InMemorySettings()
        store.loadError = TestFailure("permission denied")

        let preferences = Preferences(store: store)
        preferences.dailyFolder = "250-daily"

        XCTAssertEqual(store.saveCount, 0)
    }

    func testRememberingAVaultSavesItsBookmarkAndPath() {
        let store = InMemorySettings()
        let preferences = Preferences(store: store)

        preferences.rememberVault(at: URL(fileURLWithPath: "/Users/me/vault"), bookmark: Data([1]))

        XCTAssertEqual(store.stored?.vaultBookmark, Data([1]))
        XCTAssertEqual(store.stored?.vaultPath, "/Users/me/vault")
    }
}
