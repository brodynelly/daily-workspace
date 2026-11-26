import AppKit
import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class QuickPanelVimKeysTests: XCTestCase {
    private func makePanel(rows count: Int = 40) -> QuickPanelController {
        let panel = QuickPanelController()
        panel.rows = (0..<count).map { index in
            QuickPanelDataRow(id: "row:\(index)", title: "Row \(index)", detail: "", group: "Test")
        }
        return panel
    }

    private func press(_ panel: QuickPanelController, _ keys: String, modifiers: NSEvent.ModifierFlags = []) {
        for key in keys {
            XCTAssertTrue(panel.handleKey(keyCode: 0, characters: String(key), modifiers: modifiers))
        }
    }

    func testMovementKeys() {
        let panel = makePanel()
        press(panel, "jjj")
        XCTAssertEqual(panel.selectedIndex, 3)
        press(panel, "k")
        XCTAssertEqual(panel.selectedIndex, 2)
        press(panel, "G")
        XCTAssertEqual(panel.selectedIndex, 39)
        press(panel, "g")
        XCTAssertEqual(panel.selectedIndex, 39, "A lone g waits for the second key")
        press(panel, "g")
        XCTAssertEqual(panel.selectedIndex, 0)
        press(panel, "d", modifiers: .control)
        XCTAssertGreaterThan(panel.selectedIndex, 0)
        press(panel, "u", modifiers: .control)
        XCTAssertEqual(panel.selectedIndex, 0)
        press(panel, "f", modifiers: .control)
        let page = panel.selectedIndex
        XCTAssertGreaterThan(page, 1)
        press(panel, "b", modifiers: .control)
        XCTAssertEqual(panel.selectedIndex, 0)
    }

    func testRouteKeysSearchAndBack() {
        let panel = makePanel()
        press(panel, "2")
        XCTAssertEqual(panel.currentRoute, .agents)
        press(panel, "9")
        XCTAssertEqual(panel.currentRoute, .shortcuts)
        press(panel, "]")
        XCTAssertEqual(panel.currentRoute, .attention)
        press(panel, "[")
        XCTAssertEqual(panel.currentRoute, .shortcuts)
        press(panel, "h")
        XCTAssertEqual(panel.currentRoute, .attention, "h walks back through history")
        press(panel, "hhh")
        XCTAssertEqual(panel.currentRoute, .home)
        press(panel, "h")
        XCTAssertEqual(panel.currentRoute, .home, "h never hides the panel")
        press(panel, "/")
        XCTAssertEqual(panel.focusedPane, "command")
        XCTAssertFalse(
            panel.handleKey(keyCode: 38, characters: "j", typedCharacters: "j"), "Letters type into active search")
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertEqual(panel.focusedPane, "document")
        press(panel, "z")
        XCTAssertTrue(panel.zoomed)
    }

    func testMusicKeys() {
        let panel = makePanel(rows: 3)
        panel.currentRoute = .music
        var actions: [String] = []
        panel.onMusicAction = { actions.append(String(describing: $0)) }
        press(panel, "np-+")
        XCTAssertEqual(actions.count, 4)
        XCTAssertTrue(actions[2].contains("-10") && actions[3].contains("10"))
        press(panel, "h")
        XCTAssertEqual(panel.focusedPane, "playlists")
        press(panel, "l")
        XCTAssertEqual(panel.focusedPane, "document")
    }

    func testPlainLettersCannotBeBoundAsPanelShortcuts() {
        let letter = ShortcutBinding(ShortcutStroke("j"))
        XCTAssertEqual(KeyboardShortcutCatalog.validate(letter, context: .quickPanel), .reservedStroke)
        let command = ShortcutBinding(ShortcutStroke("j", modifiers: .command))
        XCTAssertNil(KeyboardShortcutCatalog.validate(command, context: .quickPanel))
    }

    func testFooterAdvertisesNoFunctionKeys() {
        let panel = QuickPanelController()
        for route in [QuickPanelRoute.home, .music] {
            panel.currentRoute = route
            XCTAssertFalse(panel.vimHints.contains { $0.0.hasPrefix("F") }, "\(route)")
        }
    }
}
