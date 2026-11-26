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

    func testQuestionMarkOpensAIPageAndSlashOpensSearch() {
        let panel = QuickPanelController()
        XCTAssertTrue(panel.handleKey(keyCode: 44, characters: "/"))
        XCTAssertEqual(panel.focusedPane, "command")
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertEqual(panel.focusedPane, "document")

        XCTAssertTrue(panel.handleKey(keyCode: 44, characters: "?", modifiers: .shift))
        XCTAssertTrue(panel.aiPopup.isVisible)
        // Typing, including vim letters and `?`, belongs to the AI field.
        XCTAssertFalse(panel.handleKey(keyCode: 38, characters: "j"))
        XCTAssertFalse(panel.handleKey(keyCode: 44, characters: "?", modifiers: .shift))
        XCTAssertEqual(panel.query, "")
        XCTAssertEqual(panel.vimHints.first?.1, "Ask")
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertFalse(panel.aiPopup.isVisible)
    }

    func testMonitorSortKeys() {
        let panel = QuickPanelController()
        panel.navigate(to: .monitor)
        panel.monitor.apply(processes: [
            .init(pid: 5, cpu: 1, memoryPercent: 0, residentKB: 900, name: "beta"),
            .init(pid: 9, cpu: 40, memoryPercent: 0, residentKB: 100, name: "Alpha"),
        ])
        panel.updateRows()
        XCTAssertEqual(panel.monitor.sortedProcesses.map(\.pid), [9, 5], "CPU, highest first")
        XCTAssertTrue(panel.handleKey(keyCode: 47, characters: ">", modifiers: .shift))
        XCTAssertEqual(panel.monitor.sort, .pid)
        XCTAssertEqual(panel.monitor.sortedProcesses.map(\.pid), [5, 9])
        XCTAssertTrue(panel.handleKey(keyCode: 43, characters: "<", modifiers: .shift))
        XCTAssertTrue(panel.handleKey(keyCode: 43, characters: "<", modifiers: .shift))
        XCTAssertEqual(panel.monitor.sort, .memory)
        XCTAssertEqual(panel.rows.map(\.id), ["process:5", "process:9"])
        XCTAssertTrue(panel.handleKey(keyCode: 34, characters: "i"))
        XCTAssertEqual(panel.rows.map(\.id), ["process:9", "process:5"])
    }

    func testKeyCapsSplitStrokesAndShowControl() {
        XCTAssertEqual(QuickPanelKeyCaps.strokes("^B D"), ["⌃B", "D"])
        XCTAssertEqual(QuickPanelKeyCaps.strokes("[ ]"), ["[", "]"])
        XCTAssertEqual(QuickPanelKeyCaps.strokes(" j/k "), ["j/k"])
    }
}
