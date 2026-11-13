import AppKit
import DailyCore
import Foundation
import SwiftUI
import XCTest

@testable import DailyWorkspace

@MainActor
final class QuickPanelUIIntegrationTests: XCTestCase {
    func testPascalSkinLaysOutLiveSystemRows() {
        let panel = QuickPanelController()
        panel.navigate(to: .system)
        let host = NSHostingView(rootView: QuickPanelPascalSkin(controller: panel))
        host.frame = NSRect(x: 0, y: 0, width: 1060, height: 680)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.rootView.controller.rows.count, QuickPanelSystemAction.allCases.count)
    }

    func testQuickAIChatFileMenuOpensSharedAssistant() throws {
        let panel = QuickPanelController()
        var opened: AppSection?
        panel.openWorkspace = { opened = $0 }
        let fileMenu = panel.panelMenu(named: "File")
        let item = try XCTUnwrap(fileMenu.items.first { $0.title == "Quick AI Chat" })
        XCTAssertEqual(item.representedObject as? String, "assistant")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(opened, .assistant)
        XCTAssertEqual(panel.currentRoute, .home)
    }

    func testEndShuffleMenuDispatchesMusicActionWithoutAutomation() throws {
        let panel = QuickPanelController()
        panel.currentRoute = .music
        var dispatched = false
        panel.onMusicAction = { action in
            if case .endShuffle = action { dispatched = true }
        }
        let menu = panel.panelMenu(named: "Shuffle")
        let item = try XCTUnwrap(menu.items.first { $0.title == "End Shuffle" })
        XCTAssertEqual(item.representedObject as? String, "endShuffle")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertTrue(dispatched)
    }

    func testSystemRowsSearchSelectionAndEscapeLadder() {
        let panel = QuickPanelController()
        panel.navigate(to: .system)
        XCTAssertEqual(panel.rows.map(\.title), QuickPanelSystemAction.allCases.map(\.title))
        panel.query = "BT Restart"
        XCTAssertEqual(panel.rows.map(\.title), ["BT Restart"])
        panel.escape()
        XCTAssertEqual(panel.query, "")
        XCTAssertEqual(panel.rows.count, QuickPanelSystemAction.allCases.count)
        panel.escape()
        XCTAssertEqual(panel.currentRoute, .home)
    }

    func testKeyboardNavigationHistorySelectionAndPaneCycle() {
        let panel = QuickPanelController()
        XCTAssertTrue(panel.handleKey(keyCode: 18, characters: "1", modifiers: .command))
        XCTAssertEqual(panel.currentRoute, .home)
        XCTAssertTrue(panel.handleKey(keyCode: 19, characters: "2", modifiers: .command))
        XCTAssertEqual(panel.currentRoute, .agents)
        XCTAssertTrue(panel.handleKey(keyCode: 0, characters: "a"))
        XCTAssertEqual(panel.query, "a")
        XCTAssertEqual(panel.focusedPane, "command")
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertEqual(panel.query, "")
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertEqual(panel.currentRoute, .home)
        XCTAssertTrue(panel.handleKey(keyCode: 48))
        XCTAssertEqual(panel.focusedPane, "document")
        XCTAssertTrue(panel.handleKey(keyCode: 48, modifiers: .shift))
        XCTAssertEqual(panel.focusedPane, "command")
    }

    func testSystemRowKeyboardSelectionClampAndFind() {
        let panel = QuickPanelController()
        panel.navigate(to: .system)
        XCTAssertTrue(panel.handleKey(keyCode: 119))  // End
        XCTAssertEqual(panel.selectedIndex, panel.rows.count - 1)
        XCTAssertTrue(panel.handleKey(keyCode: 125))  // Down clamps
        XCTAssertEqual(panel.selectedIndex, panel.rows.count - 1)
        XCTAssertTrue(panel.handleKey(keyCode: 115))  // Home
        XCTAssertEqual(panel.selectedIndex, 0)
        XCTAssertTrue(panel.handleKey(keyCode: 99))  // F3
        XCTAssertEqual(panel.focusedPane, "command")
        XCTAssertTrue(panel.handleKey(keyCode: 120))  // F2
        XCTAssertEqual(panel.currentRoute, .agents)
        XCTAssertTrue(panel.handleKey(keyCode: 21, characters: "4", modifiers: .command))
        XCTAssertEqual(panel.currentRoute, .files)
    }

    func testReboundPanelRouteNoLongerUsesItsOriginalKey() throws {
        let panel = QuickPanelController()
        let model = AppModel(dependencies: .test())
        panel.model = model
        try KeyboardShortcutCatalog.set(
            ShortcutBinding(ShortcutStroke("j", modifiers: .command)),
            for: "panel.agents", preferences: model.preferences
        ).get()
        XCTAssertFalse(panel.handleKey(keyCode: 19, characters: "2", modifiers: .command))
        XCTAssertEqual(panel.currentRoute, .home)
        XCTAssertTrue(panel.handleKey(keyCode: 38, characters: "j", modifiers: .command))
        XCTAssertEqual(panel.currentRoute, .agents)

        try KeyboardShortcutCatalog.set(nil, for: "panel.files", preferences: model.preferences).get()
        XCTAssertFalse(panel.handleKey(keyCode: 21, characters: "4", modifiers: .command))
        XCTAssertEqual(panel.currentRoute, .agents)
    }

    func testMusicPlaylistPaneConsumesArrowsAndReturnFocusesSongs() {
        let panel = QuickPanelController()
        panel.navigate(to: .music)
        panel.focusedPane = "playlists"
        XCTAssertTrue(panel.handleKey(keyCode: 125))
        XCTAssertEqual(panel.focusedPane, "playlists")
        XCTAssertTrue(panel.handleKey(keyCode: 36))
        XCTAssertEqual(panel.focusedPane, "document")
    }

    func testTypedDirectoryRequiresExistingDirectoryAndExplicitRoute() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let row = try XCTUnwrap(quickPanelTypedDirectoryRow(folder.path, for: .home))
        XCTAssertEqual(row.action, .openTarget(folder.path))
        XCTAssertEqual(row.title, "New session at \(folder.path)")
        let panel = QuickPanelController()
        panel.query = folder.path
        XCTAssertEqual(panel.rows.first?.action, .openTarget(folder.path))
        panel.navigate(to: .music)
        panel.query = folder.path
        XCTAssertFalse(panel.rows.contains { $0.action == .openTarget(folder.path) })
        XCTAssertNil(quickPanelTypedDirectoryRow(folder.path, for: .music))
        XCTAssertNil(quickPanelTypedDirectoryRow(folder.appendingPathComponent("missing").path, for: .home))
    }

    func testControlInspectionAcknowledgesSuccessfulResponse() {
        let panel = QuickPanelController()
        let response = panel.handleControlAction(.inspect)
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["view"] as? String, "home")
    }

    func testControlResponseNeverReadsOrReportsClipboardActivityWithoutOptIn() {
        let panel = QuickPanelController()
        let model = AppModel(dependencies: .test())
        panel.model = model
        XCTAssertNil(panel.handleControlAction(.inspect)["clipboard_change_count"])

        model.preferences.quickPanelClipboardEnabled = true
        XCTAssertNotNil(panel.handleControlAction(.inspect)["clipboard_change_count"])

        model.preferences.quickPanelClipboardEnabled = false
        XCTAssertNil(panel.handleControlAction(.inspect)["clipboard_change_count"])
    }

    func testUnavailableAttentionInventoryIsNotEmptyState() {
        let panel = QuickPanelController()
        panel.navigate(to: .attention)
        XCTAssertEqual(panel.rows.first?.title, "Loading attention inventory")
        XCTAssertNil(panel.rows.first?.action)
        XCTAssertEqual(panel.rows.first?.group, "Attention")
    }
}
