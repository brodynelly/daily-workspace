import AppKit
import Foundation
import XCTest

@testable import DailyWorkspace

@MainActor
final class QuickPanelParitySafetyTests: XCTestCase {
    func testPageDownMovesByVisibleRowsAndTypeToSearchUsesTypedCase() {
        let panel = QuickPanelController()
        panel.rows = (0..<40).map { index in
            QuickPanelDataRow(id: "row:\(index)", title: "Row \(index)", detail: "", group: "Test")
        }
        XCTAssertTrue(panel.handleKey(keyCode: 121))
        XCTAssertGreaterThan(panel.selectedIndex, 6)
        XCTAssertTrue(panel.handleKey(keyCode: 116))
        XCTAssertEqual(panel.selectedIndex, 0)

        XCTAssertTrue(panel.handleKey(keyCode: 0, characters: "a", modifiers: .shift, typedCharacters: "A"))
        XCTAssertEqual(panel.query, "A")
    }

    func testNotificationColdLaunchDoesNotActivateButInteractiveLaunchDoes() {
        XCTAssertFalse(
            WorkspaceAppDelegate.shouldActivateOnLaunch(arguments: ["DailyWorkspace", "--background-control"]))
        XCTAssertFalse(
            WorkspaceAppDelegate.shouldActivateOnLaunch(
                arguments: ["DailyWorkspace", "--background-control", "--config", "/tmp/quick-panel.json"]))
        XCTAssertTrue(WorkspaceAppDelegate.shouldActivateOnLaunch(arguments: ["DailyWorkspace"]))
        XCTAssertTrue(WorkspaceAppDelegate.shouldActivateOnLaunch(arguments: ["DailyWorkspace", "--config", "/tmp/x"]))
    }

    func testMouseCornerTargetsVisibleLowerRightWithinScreenBounds() throws {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 1440, y: -900, width: 1920, height: 860)
        let corner = try XCTUnwrap(
            QuickPanelController.mouseTarget(
                position: "corner", visibleFrame: visible, primaryScreenMaxY: primary.maxY))
        XCTAssertEqual(corner.x, 3260)
        XCTAssertEqual(corner.y, 1700)
        let center = try XCTUnwrap(
            QuickPanelController.mouseTarget(
                position: "center", visibleFrame: visible, primaryScreenMaxY: primary.maxY))
        XCTAssertEqual(center.x, 2400)
        XCTAssertEqual(center.y, 1370)
        let narrow = try XCTUnwrap(
            QuickPanelController.mouseTarget(
                position: "corner", visibleFrame: CGRect(x: 10, y: 20, width: 30, height: 40),
                primaryScreenMaxY: 900))
        XCTAssertEqual(narrow.x, 11)
        XCTAssertEqual(narrow.y, 841)
    }

    func testZenMouseRequiresOptInPermissionAndOnlyZenActivation() throws {
        var config = try JSONDecoder().decode(
            QuickPanelControlConfiguration.self, from: Data(#"{"zen_mouse":true}"#.utf8))
        XCTAssertTrue(config.shouldCenterMouse(applicationName: "Zen Browser", accessibilityTrusted: true))
        XCTAssertFalse(config.shouldCenterMouse(applicationName: "Zen Browser", accessibilityTrusted: false))
        XCTAssertFalse(config.shouldCenterMouse(applicationName: "Safari", accessibilityTrusted: true))
        XCTAssertFalse(config.shouldCenterMouse(applicationName: nil, accessibilityTrusted: true))
        config.zenMouse = false
        XCTAssertFalse(config.shouldCenterMouse(applicationName: "Zen Browser", accessibilityTrusted: true))
    }

    func testStoppedAttentionWatcherCannotOpenPanelDuringSleepOrRestart() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-panel-attention-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("[]".utf8).write(to: file)
        let attention = QuickPanelAttention(fileURL: file, pollInterval: 3_600)
        var openings = 0
        attention.onNewAttention = { _ in openings += 1 }
        await attention.start()
        attention.stop()

        func agent(_ id: Int) -> String {
            "{\"id\":\(id),\"status\":\"attention\",\"generation\":1,\"instance\":\"agent-\(id)\"}"
        }
        try Data("[\(agent(7))]".utf8).write(to: file, options: .atomic)
        await attention.refresh()
        XCTAssertEqual(openings, 0)
        await attention.start()
        XCTAssertEqual(openings, 0)
        defer { attention.stop() }
        try Data("[\(agent(7)),\(agent(8))]".utf8).write(to: file, options: .atomic)
        await attention.refresh()
        XCTAssertEqual(openings, 1)
    }
}
