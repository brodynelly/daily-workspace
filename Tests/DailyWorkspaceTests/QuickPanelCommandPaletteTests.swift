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

    func testMenuKeyOpensMenuInPopupStyle() {
        let panel = QuickPanelController()
        XCTAssertTrue(panel.handleKey(keyCode: 46, characters: "m"))
        XCTAssertTrue(panel.palette.isVisible)
        XCTAssertEqual(panel.palette.title, "MENU")
        XCTAssertTrue(panel.visiblePaletteItems.contains { $0.group == "File" && $0.title == "Refresh" })
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertFalse(panel.palette.isVisible)

        XCTAssertTrue(panel.handleKey(keyCode: 3, characters: "f", modifiers: .option))
        XCTAssertEqual(panel.palette.title, "FILE")
        XCTAssertTrue(panel.visiblePaletteItems.allSatisfy { $0.group == "File" })
    }

    func testQuestionMarkOpensAIPaneAndSlashOpensSearch() {
        let panel = QuickPanelController()
        XCTAssertTrue(panel.handleKey(keyCode: 44, characters: "/"))
        XCTAssertEqual(panel.focusedPane, "command")
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertEqual(panel.focusedPane, "document")

        XCTAssertTrue(panel.handleKey(keyCode: 44, characters: "?", modifiers: .shift))
        XCTAssertTrue(panel.assistantVisible)
        XCTAssertEqual(panel.focusedPane, "assistant")
        // Typing, including vim letters and `?`, belongs to the AI field.
        XCTAssertFalse(panel.handleKey(keyCode: 38, characters: "j"))
        XCTAssertFalse(panel.handleKey(keyCode: 44, characters: "?", modifiers: .shift))
        XCTAssertTrue(panel.assistantVisible)
        XCTAssertEqual(panel.query, "")

        XCTAssertTrue(panel.handleKey(keyCode: 48))
        XCTAssertEqual(panel.focusedPane, "document")
        XCTAssertTrue(panel.handleKey(keyCode: 44, characters: "?", modifiers: .shift))
        XCTAssertFalse(panel.assistantVisible)
    }

    func testKeyCapsSplitStrokesAndShowControl() {
        XCTAssertEqual(QuickPanelKeyCaps.strokes("^B D"), ["⌃B", "D"])
        XCTAssertEqual(QuickPanelKeyCaps.strokes("[ ]"), ["[", "]"])
        XCTAssertEqual(QuickPanelKeyCaps.strokes(" j/k "), ["j/k"])
    }
}
