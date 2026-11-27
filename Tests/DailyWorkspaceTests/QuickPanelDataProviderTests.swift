import Foundation
import XCTest

@testable import DailyWorkspace

private actor PanelFakeRunner {
    var outputs: [String: QuickPanelCommandOutput] = [:]
    var invocations: [[String]] = []

    func set(_ suffix: String, data: Data, status: Int32 = 0) {
        outputs[suffix] = .init(stdout: data, exitStatus: status)
    }

    func run(_ executable: URL, _ arguments: [String], _ environment: [String: String]) throws
        -> QuickPanelCommandOutput
    {
        invocations.append(arguments)
        guard
            let key = outputs.keys.first(where: { key in
                let parts = key.split(separator: " ", maxSplits: 1)
                return arguments.first?.hasSuffix(String(parts[0])) == true
                    && (parts.count == 1 || (arguments.count > 1 && arguments[1] == String(parts[1])))
            }),
            let output = outputs[key]
        else { throw QuickPanelCommandError.ioFailed }
        return output
    }

    func calls() -> [[String]] { invocations }
}

@MainActor
final class QuickPanelDataProviderTests: XCTestCase {
    private func directory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    @MainActor
    private func provider(home: URL, bundled: URL, fake: PanelFakeRunner) -> QuickPanelDataProvider {
        QuickPanelDataProvider(
            home: home, dotfiles: home.appendingPathComponent("dotfiles"),
            bundledShortcuts: bundled, desktopDiscovery: { [] }, rexExecutable: nil,
            run: { executable, arguments, environment in
                try await fake.run(executable, arguments, environment)
            })
    }

    func testMalformedAndPartialHelperResponsesRemainUnavailableOrSkipBadRows() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = PanelFakeRunner()
        await fake.set("kitty_sessions.py", data: Data("{broken".utf8))
        await fake.set("kitty-zoxide-session.sh", data: Data([0xFF]))
        let data = await provider(home: root, bundled: root, fake: fake)
        await data.refresh()
        var snapshot = await data.snapshot
        XCTAssertNil(snapshot.rows(for: .agents).first?.action)
        XCTAssertNil(snapshot.rows(for: .ssh).first?.action)
        XCTAssertTrue(snapshot.notices.contains("Invalid Kitty sessions response"))
        XCTAssertTrue(snapshot.notices.contains("Invalid targets response"))

        let partial = """
            {"kitty":true,"agents":[{"id":12,"title":"Valid","cwd":"/tmp"},{"id":"bad","title":"Invalid"},false],
             "sessions":[{"name":"work","path":"/tmp","tabs":2},{"tabs":5}],
             "files":[{"name":"home","path":"/tmp/home.kitty-session"},{"name":"broken"}]}
            """
        await fake.set("kitty_sessions.py", data: Data(partial.utf8))
        await fake.set(
            "kitty-zoxide-session.sh", data: Data("/tmp/project\tproject\nssh:example\tremote\ntmux:dev\tdev\n".utf8))
        await data.refresh()
        snapshot = await data.snapshot
        XCTAssertEqual(snapshot.agents.count, 1)
        XCTAssertEqual(snapshot.agents.first?.action, .focusAgent(12))
        XCTAssertEqual(snapshot.sessions.first?.remove, .closeSession("work"))
        XCTAssertEqual(snapshot.files.count, 1)
        XCTAssertEqual(snapshot.projects.first?.alternate, .workspaceActions("/tmp/project"))
        XCTAssertEqual(snapshot.ssh.first?.action, .openTarget("ssh:example"))
        XCTAssertEqual(snapshot.tmux.first?.action, .openTarget("tmux:dev"))
        XCTAssertEqual(snapshot.searchRows(for: .home).filter { $0.action != nil }.count, 6)
    }

    func testWorkspaceCatalogIncludesPathsOutsideFixedRootsAndActionsAreDeferred() async throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        let child = home.appendingPathComponent("github/special/catalog-only")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("dotfiles"), withIntermediateDirectories: true)
        let fake = PanelFakeRunner()
        await fake.set(
            "kitty_sessions.py", data: Data("{\"kitty\":false,\"agents\":[],\"sessions\":[],\"files\":[]}".utf8))
        await fake.set("kitty-zoxide-session.sh", data: Data())
        let catalog = try JSONSerialization.data(
            withJSONObject: [
                ["name": "Catalog only", "path": child.path],
                ["name": "Invalid relative path", "path": "relative"],
            ])
        await fake.set("workspace.py catalog", data: catalog)
        await fake.set(
            "workspace.py actions",
            data: Data("[{\"name\":\"Codex CLI\",\"tool\":\"codex\"},{\"name\":\"bad\",\"tool\":\"../escape\"}]".utf8))
        let data = await provider(home: home, bundled: home, fake: fake)
        await data.refresh()
        let snapshot = data.snapshot
        XCTAssertEqual(snapshot.workspaces.map(\.title), ["Catalog only"])
        XCTAssertEqual(snapshot.workspaces.first?.action, .workspaceActions(child.path))
        XCTAssertTrue(snapshot.notices.contains("Invalid workspace catalog entries skipped"))
        let initialCalls = await fake.calls()
        XCTAssertEqual(initialCalls.count, 3)
        XCTAssertTrue(initialCalls.contains { $0.count == 2 && $0[1] == "catalog" })
        let actions = await data.workspaceActions(for: child.path)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.action, .launch(path: child.path, tool: "codex"))
        let calls = await fake.calls()
        XCTAssertEqual(
            calls.last,
            [
                home.appendingPathComponent("dotfiles/scripts/macos/mac/agents/workspace.py").path,
                "actions", child.path,
            ])
    }

    func testShortcutIndexRejectsPathEscapeAndFallsBackToBundledToolFile() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("dotfiles/hammerspoon/shortcuts")
        let bundled = root.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        let index = """
            {"groups":[{"title":"Global","tools":[{"id":"../outside","title":"Escaped"},
              {"id":"safe","title":"Safe","subtitle":"keys"}]}]}
            """
        try Data(index.utf8).write(to: local.appendingPathComponent("index.json"))
        try Data("{invalid".utf8).write(to: local.appendingPathComponent("safe.json"))
        try Data("{\"sections\":[{\"title\":\"Keys\",\"rows\":[{\"label\":\"Open\",\"keys\":[[\"⌘\",\"O\"]]}]}]}".utf8)
            .write(to: bundled.appendingPathComponent("safe.json"))
        let fake = PanelFakeRunner()
        await fake.set(
            "kitty_sessions.py", data: Data("{\"kitty\":true,\"agents\":[],\"sessions\":[],\"files\":[]}".utf8))
        await fake.set("kitty-zoxide-session.sh", data: Data())
        let data = provider(home: root, bundled: bundled, fake: fake)
        await data.refresh()
        var snapshot = data.snapshot
        XCTAssertEqual(snapshot.shortcutTools.map(\.title), ["Safe"])
        XCTAssertEqual(snapshot.rows(for: .shortcuts, shortcutTool: "safe").first?.keys, "⌘ O")
        XCTAssertEqual(snapshot.searchRows(for: .shortcuts).count, 2)
        XCTAssertTrue(
            snapshot.rows(for: .shortcuts, shortcutTool: "safe").first?.keywords.contains("cmd command") == true)
        let escapedFile = root.appendingPathComponent("outside.json")
        try Data("{\"sections\":[{\"title\":\"Bad\",\"rows\":[{\"label\":\"Escaped file\"}]}]}".utf8)
            .write(to: escapedFile)
        try FileManager.default.removeItem(at: local.appendingPathComponent("safe.json"))
        try FileManager.default.createSymbolicLink(
            at: local.appendingPathComponent("safe.json"), withDestinationURL: escapedFile)
        await data.refresh()
        snapshot = data.snapshot
        XCTAssertEqual(snapshot.rows(for: .shortcuts, shortcutTool: "safe").first?.title, "Open")
        try Data("{invalid".utf8).write(to: local.appendingPathComponent("index.json"))
        try Data(index.replacingOccurrences(of: "../outside", with: "also_safe").utf8)
            .write(to: bundled.appendingPathComponent("index.json"))
        await data.refresh()
        snapshot = data.snapshot
        XCTAssertEqual(snapshot.shortcutTools.map(\.title), ["Escaped", "Safe"])
    }
}
