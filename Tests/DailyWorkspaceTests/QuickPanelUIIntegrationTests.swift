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

    func testPanelStaysVisibleForNativeMenusButHidesWhenAnotherAppTakesFocus() {
        let controller = QuickPanelController()
        controller.panel.setFrame(NSRect(x: -10_000, y: -10_000, width: 1060, height: 680), display: false)
        controller.panel.orderFront(nil)
        defer { controller.panel.orderOut(nil) }
        XCTAssertTrue(controller.panel.isVisible)

        controller.dismissAfterKeyLoss(frontmostPID: ProcessInfo.processInfo.processIdentifier)
        XCTAssertTrue(controller.panel.isVisible)
        controller.dismissAfterKeyLoss(frontmostPID: nil)
        XCTAssertTrue(controller.panel.isVisible)

        controller.dismissAfterKeyLoss(frontmostPID: ProcessInfo.processInfo.processIdentifier + 1)
        XCTAssertFalse(controller.panel.isVisible)
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

    func testProjectWorkspaceActionsDisplayFailureInsteadOfLeavingProjectsRows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let panel = QuickPanelController()
        var configuration = QuickPanelControlConfiguration()
        configuration.dotfiles = root.path
        configuration.attentionFile = root.appendingPathComponent("attention.json").path
        panel.configure(model: AppModel(dependencies: .test()), configuration: configuration)
        panel.navigate(to: .projects)
        let path = root.appendingPathComponent("project").path
        panel.rows = [
            .init(id: "project", title: "Project", detail: "", group: "Projects", action: .workspaceActions(path))
        ]
        panel.activateSelected()
        for _ in 0..<100 where panel.workspaceRows.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(panel.workspacePath, path)
        XCTAssertEqual(panel.rows.first?.title, "Launch unavailable")
        XCTAssertEqual(panel.rows.first?.detail, "Workspace actions could not be loaded")
    }

    func testHeldNavigationRepeatsButPanelActionsDoNot() throws {
        func key(
            _ code: UInt16, repeating: Bool = true, modifiers: NSEvent.ModifierFlags = []
        ) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: repeating, keyCode: code))
        }

        let panel = QuickPanelController()
        panel.navigate(to: .system)
        panel.rows = (0..<40).map {
            QuickPanelDataRow(id: "row:\($0)", title: "Row \($0)", detail: "", group: "Test")
        }
        XCTAssertTrue(panel.handleKey(try key(125)))
        XCTAssertTrue(panel.handleKey(try key(125)))
        XCTAssertEqual(panel.selectedIndex, 2)
        XCTAssertTrue(panel.handleKey(try key(121)))
        XCTAssertEqual(panel.selectedIndex, 18)  // 680pt panel: (506pt document - 34pt viewport inset) / 28pt.
        XCTAssertTrue(panel.handleKey(try key(115)))
        XCTAssertEqual(panel.selectedIndex, 0)
        XCTAssertTrue(panel.handleKey(try key(119)))
        XCTAssertEqual(panel.selectedIndex, 39)
        XCTAssertTrue(panel.handleKey(try key(116)))
        XCTAssertEqual(panel.selectedIndex, 23)

        panel.navigate(to: .music)
        var actions = 0
        panel.onMusicAction = { _ in actions += 1 }
        XCTAssertTrue(panel.handleKey(try key(100, repeating: false)))  // F8 play/pause
        XCTAssertTrue(panel.handleKey(try key(100)))
        XCTAssertEqual(actions, 1)
        panel.focusedPane = "command"
        XCTAssertFalse(panel.handleKey(try key(51, modifiers: .option)), "Held Option-Delete must reach search.")
        XCTAssertTrue(
            panel.handleKey(try key(51, modifiers: .command)), "Held Command-Delete must not repeat an action.")
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

    func testEscapeRestoresMusicFromAnotherRouteAndLeavesMusicOnBack() {
        let panel = QuickPanelController()
        panel.navigate(to: .music)
        panel.navigate(to: .system)
        panel.escape()
        XCTAssertEqual(panel.currentRoute, .music)
        panel.escape()
        XCTAssertEqual(panel.currentRoute, .home)
    }

    func testAttentionWarningIsDisplayOnlyAndRetainsSourceMetadata() {
        let panel = QuickPanelController()
        panel.navigate(to: .attention)
        let row = QuickPanelDataRow(
            id: "attention:test", title: "Agent needs input", detail: "/tmp/project",
            group: "Attention", status: "waiting")
        panel.rows = [row]
        panel.attentionIdentities[row.id] = .init(id: 1, instance: "test", generation: 1, reason: "question")
        let skin = QuickPanelPascalSkin(controller: panel)
        XCTAssertEqual(skin.displayTitle(for: row), "! Agent needs input")
        XCTAssertEqual(panel.rows[0].title, "Agent needs input")
        XCTAssertEqual(panel.rows[0].status, "waiting")
        panel.navigate(to: .system)
        XCTAssertEqual(QuickPanelPascalSkin(controller: panel).displayTitle(for: row), "Agent needs input")
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

extension QuickPanelUIIntegrationTests {
    func testPointerSelectionsRestoreKeyboardPaneAndTypeToSearch() {
        let panel = QuickPanelController()
        panel.navigate(to: .system)
        panel.focusedPane = "command"
        panel.selectResultFromPointer(1)
        XCTAssertEqual(panel.selectedIndex, 1)
        XCTAssertEqual(panel.focusedPane, "document")
        XCTAssertTrue(panel.handleKey(keyCode: 0, characters: "s"))
        XCTAssertEqual(panel.query, "s")
        XCTAssertEqual(panel.focusedPane, "command")

        panel.navigate(to: .music)
        panel.focusedPane = "command"
        panel.selectPlaylistFromPointer("missing")
        XCTAssertEqual(panel.focusedPane, "playlists")
        var actions = 0
        panel.onMusicAction = { _ in actions += 1 }
        XCTAssertTrue(panel.handleKey(keyCode: 49))
        XCTAssertEqual(actions, 1, "Space controls Music after playlist selection")
        panel.selectResultFromPointer(0)
        XCTAssertEqual(panel.focusedPane, "document")
        XCTAssertTrue(panel.handleKey(keyCode: 0, characters: "a"))
        XCTAssertEqual(panel.query, "a")
        XCTAssertEqual(panel.focusedPane, "command")
    }

    func testMusicVolumeFunctionKeysAndMenusUseTenPercentSteps() throws {
        let panel = QuickPanelController()
        panel.currentRoute = .music
        var deltas: [Int] = []
        panel.onMusicAction = { action in
            if case .volume(let delta) = action { deltas.append(delta) }
        }

        XCTAssertTrue(panel.handleKey(keyCode: 96))
        XCTAssertTrue(panel.handleKey(keyCode: 97))
        let menu = panel.panelMenu(named: "Play")
        for title in ["Volume down", "Volume up"] {
            let item = try XCTUnwrap(menu.items.first { $0.title == title })
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        }
        XCTAssertEqual(deltas, [-10, 10, -10, 10])
        XCTAssertTrue(panel.handleKey(keyCode: 27, characters: "-", modifiers: [.command]))
        XCTAssertEqual(deltas.last, -5, "⌘− keeps its separate five-percent step")
    }

    func testSuccessfulMusicActionClearsStaleBusyFeedback() async {
        let panel = QuickPanelController()
        panel.currentRoute = .music
        panel.reportError("Music is finishing another action.")
        let cleared = expectation(description: "Music action clears stale feedback")
        panel.onErrorChange = { message in
            if message == nil { cleared.fulfill() }
        }

        panel.performMusic(.endShuffle)
        await fulfillment(of: [cleared], timeout: 1)
        XCTAssertNil(panel.error)
    }

}
