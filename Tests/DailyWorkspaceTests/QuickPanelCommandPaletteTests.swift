import AppKit
import XCTest

@testable import DailyWorkspace

@MainActor
final class QuickPanelCommandPaletteTests: XCTestCase {
    func testCommandPaletteShortcutStaysInsidePanel() {
        let panel = QuickPanelController()
        var opened: AppSection?
        panel.openWorkspace = { opened = $0 }
        XCTAssertTrue(panel.handleKey(keyCode: 40, characters: "k", modifiers: .command))
        XCTAssertTrue(panel.palette.isVisible)
        XCTAssertNil(opened)

        for character in "proj" {
            XCTAssertTrue(panel.handleKey(keyCode: 0, characters: String(character)))
        }
        XCTAssertEqual(panel.palette.query, "proj")
        XCTAssertEqual(panel.query, "")
        XCTAssertTrue(panel.handleKey(keyCode: 36))
        XCTAssertFalse(panel.palette.isVisible)
        XCTAssertEqual(panel.currentRoute, .projects)
        XCTAssertNil(opened)

        XCTAssertTrue(panel.handleKey(keyCode: 40, characters: "k", modifiers: .command))
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertFalse(panel.palette.isVisible)
        XCTAssertEqual(panel.currentRoute, .projects)
    }
}
