import AppKit
import Combine
import Foundation
import XCTest

@testable import DailyWorkspace

private actor AttentionActionRecorder {
    private(set) var actions: [(QuickPanelAttentionAction, UInt64)] = []

    func record(_ action: QuickPanelAttentionAction, id: UInt64) {
        actions.append((action, id))
    }

    func recorded() -> [(QuickPanelAttentionAction, UInt64)] { actions }
}

@MainActor
final class QuickPanelAttentionTests: XCTestCase {
    private var directory: URL!
    private var inventory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        inventory = directory.appendingPathComponent("sketchybar-opencode-agents.json")
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func write(_ rows: String) throws {
        try Data(rows.utf8).write(to: inventory, options: .atomic)
    }

    private func agent(
        _ id: Int, status: String = "attention", generation: Int = 1,
        instance: String = "process-a", reason: String = "question", focused: Bool = false
    ) -> String {
        """
        {"id":\(id),"kind":"opencode","kind_label":"OpenCode","title":"Terminal \(id)",
         "opencode_title":"Task \(id)","cwd":"/tmp/project","session_name":"work",
         "focused":\(focused),"status":"\(status)","reason":"\(reason)",
         "instance":"\(instance)","generation":\(generation)}
        """
    }

    func testFirstValidSnapshotDoesNotOpenButNewAttentionDoes() async throws {
        try write("[\(agent(12))]")
        let source = QuickPanelAttention(fileURL: inventory, pollInterval: 3_600)
        var arrivals: [[QuickPanelAttentionIdentity]] = []
        source.onNewAttention = { arrivals.append($0.map(\.id)) }
        await source.start()
        defer { source.stop() }

        XCTAssertTrue(arrivals.isEmpty)
        XCTAssertEqual(source.sourceState, .populated)
        XCTAssertEqual(source.rows.map(\.agent.id), [12])
        let waitingSince = try XCTUnwrap(source.rows.first?.waitingSince)

        await source.refresh()
        XCTAssertTrue(arrivals.isEmpty)
        XCTAssertEqual(source.rows.first?.waitingSince, waitingSince)

        try write("[\(agent(12)),\(agent(13))]")
        await source.refresh()
        XCTAssertEqual(arrivals.count, 1)
        XCTAssertEqual(arrivals.first?.map(\.id), [13])
        await source.refresh()
        XCTAssertEqual(arrivals.count, 1)

        try write("[\(agent(12)),\(agent(13, generation: 2))]")
        await source.refresh()
        XCTAssertEqual(arrivals.count, 2)
        XCTAssertEqual(arrivals.last?.map(\.generation), [2])

        try write("[\(agent(12)),\(agent(13, generation: 2, focused: true)),\(agent(14, focused: true))]")
        await source.refresh()
        XCTAssertEqual(arrivals.count, 2)
        try write("[\(agent(12)),\(agent(13, generation: 2)),\(agent(14))]")
        await source.refresh()
        XCTAssertEqual(arrivals.count, 2, "Previously focused attention cannot auto-open later")

        try write("[\(agent(12)),\(agent(13, generation: 2, instance: "process-b", reason: "done")),\(agent(14))]")
        await source.refresh()
        XCTAssertEqual(arrivals.count, 3)
        XCTAssertEqual(arrivals.last?.first?.instance, "process-b")

        try write("[]")
        await source.refresh()
        XCTAssertEqual(source.sourceState, .empty)
        try write("[\(agent(13, generation: 2))]")
        await source.refresh()
        XCTAssertEqual(arrivals.count, 4, "Cleared attention is a new event if it returns")
    }

    func testSleepSuspendsWatcherAndWakeBaselinesExistingAttentionBeforePolling() async throws {
        try write("[\(agent(12))]")
        let source = QuickPanelAttention(fileURL: inventory, pollInterval: 3_600, observesSleep: false)
        var arrivals: [[QuickPanelAttentionIdentity]] = []
        source.onNewAttention = { arrivals.append($0.map(\.id)) }
        await source.start()
        defer { source.stop() }
        XCTAssertTrue(source.isWatching)
        let waitingSince = try XCTUnwrap(source.rows.first?.waitingSince)

        await source.setSleeping(true)
        XCTAssertFalse(source.isWatching)
        try write("[\(agent(12)),\(agent(13))]")
        await source.refresh()
        await source.start()
        XCTAssertFalse(source.isWatching, "Neither manual refresh nor start may poll during sleep")
        XCTAssertEqual(source.rows.map(\.agent.id), [12])
        XCTAssertTrue(arrivals.isEmpty)

        await source.setSleeping(false)
        XCTAssertTrue(source.isWatching)
        XCTAssertEqual(source.rows.map(\.agent.id), [12, 13])
        XCTAssertEqual(source.rows.first?.waitingSince, waitingSince)
        XCTAssertTrue(arrivals.isEmpty, "Attention already present at wake is a baseline, not a new alert")
        await source.refresh()
        XCTAssertTrue(arrivals.isEmpty)

        try write("[\(agent(12)),\(agent(13)),\(agent(14))]")
        await source.refresh()
        XCTAssertEqual(arrivals.map { $0.map(\.id) }, [[14]])

        try write("[\(agent(12)),\(agent(13, generation: 2)),\(agent(14))]")
        await source.refresh()
        XCTAssertEqual(arrivals.count, 2)
        XCTAssertEqual(arrivals.last?.map(\.generation), [2])
        await source.setSleeping(true)
        source.stop()
        await source.setSleeping(false)
        XCTAssertFalse(source.isWatching, "An explicitly stopped watcher must not restart on wake")
    }

    func testFirstValidSnapshotAfterUnavailableWakeIsStillTheWakeBaseline() async throws {
        try write("[\(agent(7))]")
        let source = QuickPanelAttention(fileURL: inventory, pollInterval: 3_600, observesSleep: false)
        var arrivals: [[QuickPanelAttentionIdentity]] = []
        source.onNewAttention = { arrivals.append($0.map(\.id)) }
        await source.start()
        defer { source.stop() }

        await source.setSleeping(true)
        try FileManager.default.removeItem(at: inventory)
        await source.setSleeping(false)
        XCTAssertTrue(source.isWatching)
        XCTAssertEqual(source.sourceState, .missing)
        XCTAssertTrue(arrivals.isEmpty)

        try write("not JSON")
        await source.refresh()
        XCTAssertEqual(source.sourceState, .invalid)
        try write("[\(agent(7)),\(agent(8))]")
        await source.refresh()
        XCTAssertEqual(source.rows.map(\.agent.id), [7, 8])
        XCTAssertTrue(arrivals.isEmpty, "A recovered file must not alert on pre-wake attention")

        try write("[\(agent(7)),\(agent(8, generation: 2))]")
        await source.refresh()
        XCTAssertEqual(arrivals.map { $0.map(\.generation) }, [[2]])
    }

    func testAutoOpenedAttentionLoadsSelectedAgentPreviewWithoutOpeningAtLaunch() async throws {
        try write("[\(agent(10))]")
        let scripts = directory.appendingPathComponent("kitty/scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try Data("printf 'preview-%s\\n' \"$2\"\n".utf8)
            .write(to: scripts.appendingPathComponent("kitty-opencode-sessions.sh"))

        let panel = QuickPanelController()
        var configuration = QuickPanelControlConfiguration()
        configuration.dotfiles = directory.path
        configuration.attentionFile = inventory.path
        panel.configure(model: AppModel(dependencies: .test()), configuration: configuration)
        defer {
            panel.attention.stop()
            panel.panel.orderOut(nil)
        }
        panel.attention.stop()
        await panel.attention.start()
        XCTAssertFalse(panel.isVisible, "The launch-time snapshot must not auto-open attention")

        let previewLoaded = expectation(description: "Selected agent preview loaded")
        let observation = panel.$attentionPreview.sink { preview in
            if preview == "preview-10" { previewLoaded.fulfill() }
        }
        defer { observation.cancel() }

        try write("[\(agent(10)),\(agent(11))]")
        await panel.attention.refresh()
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.currentRoute, .attention)
        XCTAssertEqual(panel.rows[panel.selectedIndex].title, "Task 10")
        await fulfillment(of: [previewLoaded], timeout: 3)
        XCTAssertEqual(panel.attentionPreview, "preview-10")
    }

    func testMissingAndMalformedFilesAreNotEmptyOrNewAttention() async throws {
        let source = QuickPanelAttention(fileURL: inventory, pollInterval: 3_600)
        var arrivals = 0
        source.onNewAttention = { _ in arrivals += 1 }
        await source.start()
        defer { source.stop() }
        XCTAssertEqual(source.sourceState, .missing)

        try write("[\(agent(7))]")
        await source.refresh()
        XCTAssertTrue(source.rows.map(\.agent.id) == [7])
        XCTAssertEqual(arrivals, 0, "First valid read after an unavailable startup is still a baseline")

        try write("not JSON")
        await source.refresh()
        XCTAssertEqual(source.sourceState, .invalid)
        XCTAssertTrue(source.rows.isEmpty)
        try write("[\(agent(7))]")
        await source.refresh()
        XCTAssertEqual(arrivals, 0, "Transient invalid data cannot reset attention identity")

        try FileManager.default.removeItem(at: inventory)
        await source.refresh()
        XCTAssertEqual(source.sourceState, .missing)
        try write("[]")
        await source.refresh()
        XCTAssertEqual(source.sourceState, .empty)
    }

    func testDismissFocusPreviewAndAllAgentsUseOwnerHelper() async throws {
        let unknown = agent(88, status: "unknown")
        try write("[\(agent(42)),\(unknown)]")
        let recorder = AttentionActionRecorder()
        let file = try XCTUnwrap(inventory)
        let helper = QuickPanelAttentionHelper { action, id in
            await recorder.record(action, id: id)
            if action == .preview {
                return (1...50).map { "terminal \($0)" }.joined(separator: "\n") + "\n"
            }
            if action == .dismiss {
                try Data("[\(unknown)]".utf8).write(to: file, options: .atomic)
            }
            return ""
        }
        let source = QuickPanelAttention(fileURL: inventory, helper: helper)
        await source.refresh()
        let identity = try XCTUnwrap(source.rows.first?.id)
        XCTAssertEqual(source.allAgents().map(\.status), ["attention", "unknown"])

        let preview = try await source.preview(identity)
        XCTAssertEqual(preview.split(separator: "\n").count, 40)
        XCTAssertEqual(preview.split(separator: "\n").first, "terminal 11")

        try await source.goToAgent(identity)

        try await source.dismiss(identity)
        XCTAssertEqual(source.sourceState, .populated)
        XCTAssertTrue(source.rows.isEmpty)
        XCTAssertEqual(source.allAgents().map(\.id), [88])
        do {
            try await source.goToAgent(identity)
            XCTFail("A dismissed generation must not focus an unrelated agent")
        } catch let error as QuickPanelAttentionError {
            XCTAssertEqual(error, .noLongerAvailable)
        }
        let actions = await recorder.recorded()
        XCTAssertEqual(actions.map { $0.0 }, [.preview, .focus, .dismiss])
        XCTAssertEqual(actions.map { $0.1 }, [42, 42, 42])
    }
}
