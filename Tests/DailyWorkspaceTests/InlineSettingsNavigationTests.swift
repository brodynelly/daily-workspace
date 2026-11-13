import XCTest

@testable import DailyWorkspace

@MainActor
final class InlineSettingsNavigationTests: XCTestCase {
    func testSettingsReturnsToPreviouslySelectedScreen() {
        let navigation = AppNavigation()
        navigation.section = .projects

        navigation.showSettings()
        XCTAssertTrue(navigation.showingSettings)
        XCTAssertEqual(navigation.section, .projects)

        navigation.closeSettings()
        XCTAssertFalse(navigation.showingSettings)
        XCTAssertEqual(navigation.section, .projects)
    }

    func testSettingsCanSelectRequestedTabAndKeepItOnReopen() {
        let navigation = AppNavigation()
        navigation.section = .assistant

        navigation.showSettings(tab: .ai)
        XCTAssertTrue(navigation.showingSettings)
        XCTAssertEqual(navigation.settingsTab, .ai)
        XCTAssertEqual(navigation.section, .assistant)

        navigation.closeSettings()
        navigation.showSettings()
        XCTAssertEqual(navigation.settingsTab, .ai)
    }

    func testSelectingAnyScreenLeavesSettingsEvenIfScreenIsAlreadySelected() {
        let navigation = AppNavigation()
        navigation.showSettings()
        navigation.section = .today
        XCTAssertFalse(navigation.showingSettings)

        navigation.showSettings()
        navigation.section = .notes
        XCTAssertFalse(navigation.showingSettings)
        XCTAssertEqual(navigation.section, .notes)
    }
}
