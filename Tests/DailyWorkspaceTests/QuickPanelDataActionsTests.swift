import Foundation
import XCTest

@testable import DailyWorkspace

private actor ActionFakeRunner {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let environment: [String: String]
    }

    var recorded: [Call] = []
    var status: Int32 = 0
    var error: Error?

    func run(_ executable: URL, _ arguments: [String], _ environment: [String: String]) throws
        -> QuickPanelCommandOutput
    {
        recorded.append(.init(executable: executable.path, arguments: arguments, environment: environment))
        if let error { throw error }
        return .init(stdout: Data(), exitStatus: status)
    }

    func calls() -> [Call] { recorded }
    func setStatus(_ value: Int32) { status = value }
    func setError(_ value: Error) { error = value }
}

final class QuickPanelDataActionsTests: XCTestCase {
    @MainActor
    private func actions(_ fake: ActionFakeRunner) -> QuickPanelDataActions {
        let root = URL(fileURLWithPath: "/tmp/panel-dotfiles")
        return QuickPanelDataActions(dotfiles: root) { exe, args, env in
            try await fake.run(exe, args, env)
        }
    }

    func testEveryHelperActionUsesFixedArgvAndNavigationDoesNotRunHelpers() async throws {
        let fake = ActionFakeRunner()
        let executor = await actions(fake)
        let path = "/tmp/project with $(touch /tmp/nope);'"
        let dotfiles = "/tmp/panel-dotfiles/"

        let navigation = try await executor.execute(.workspaceActions(path))
        XCTAssertEqual(navigation, .workspace(path))
        let shortcut = try await executor.execute(.shortcutTool("codex"))
        XCTAssertEqual(shortcut, .shortcut("codex"))
        let navigationCalls = await fake.calls()
        XCTAssertTrue(navigationCalls.isEmpty)

        let results = try await [
            executor.execute(.focusAgent(42)),
            executor.execute(.gotoSession("work")),
            executor.execute(.openFile("/tmp/file.kitty-session")),
            executor.execute(.openTarget("ssh:my-host")),
            executor.execute(.openTarget("tmux:session")),
            executor.execute(.openTarget(path)),
            executor.execute(.closeSession("work")),
            executor.execute(.launch(path: path, tool: "kitty:terminal-1")),
        ]
        XCTAssertEqual(results, [.hide, .hide, .hide, .hide, .hide, .hide, .stay, .hide])

        let calls = await fake.calls()
        XCTAssertEqual(
            calls.map(\.arguments),
            [
                [dotfiles + "kitty/scripts/kitty-opencode-sessions.sh", "--focus", "42"],
                [dotfiles + "scripts/macos/mac/misc/550-skhdSession.sh", "work"],
                [dotfiles + "scripts/macos/mac/misc/550-skhdSession.sh", "/tmp/file.kitty-session"],
                [dotfiles + "kitty/scripts/kitty-zoxide-session.sh", "--open", "ssh:my-host"],
                [dotfiles + "kitty/scripts/kitty-zoxide-session.sh", "--open", "tmux:session"],
                [dotfiles + "kitty/scripts/kitty-zoxide-session.sh", "--open", path],
                [dotfiles + "scripts/macos/mac/agents/kitty_sessions.py", "close", "work"],
                [dotfiles + "scripts/macos/mac/agents/workspace.py", "launch", "kitty:terminal-1", path],
            ])
        XCTAssertEqual(calls.map(\.executable).filter { $0 != "/bin/bash" }.count, 2)
        XCTAssertTrue(calls.allSatisfy { $0.environment.isEmpty })
    }

    func testInvalidSourceValuesNeverReachRunner() async throws {
        let fake = ActionFakeRunner()
        let executor = await actions(fake)
        let invalid: [QuickPanelDataAction] = [
            .focusAgent(0), .gotoSession("\n"), .closeSession("bad\0name"),
            .openFile("relative"), .openTarget("ssh:\ncommand"), .openTarget("--option"),
            .workspaceActions("relative"), .launch(path: "/tmp", tool: "x;touch"),
            .launch(path: "relative", tool: "safe"), .shortcutTool("../bad"),
        ]
        for action in invalid {
            do {
                _ = try await executor.execute(action)
                XCTFail("Accepted invalid action: \(action)")
            } catch let error as QuickPanelDataActionError {
                XCTAssertEqual(error, .invalidInput)
            }
        }
        let calls = await fake.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testTypedDirectoryUsesTargetHelper() async throws {
        let fake = ActionFakeRunner()
        let executor = await actions(fake)
        let path = FileManager.default.temporaryDirectory.path
        let result = try await executor.execute(.openTarget(path))
        XCTAssertEqual(result, .hide)
        let calls = await fake.calls()
        XCTAssertEqual(
            calls.first?.arguments,
            ["/tmp/panel-dotfiles/kitty/scripts/kitty-zoxide-session.sh", "--open", path])
    }

    func testFailureIsPropagatedWithoutReportingSuccess() async throws {
        let fake = ActionFakeRunner()
        let executor = await actions(fake)
        await fake.setStatus(19)
        do {
            _ = try await executor.execute(.closeSession("work"))
            XCTFail("Nonzero exit must fail")
        } catch let error as QuickPanelDataActionError {
            XCTAssertEqual(error, .exited(19))
        }
        await fake.setError(QuickPanelCommandError.timedOut)
        do {
            _ = try await executor.execute(.focusAgent(42))
            XCTFail("Runner error must propagate")
        } catch let error as QuickPanelCommandError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testDesktopActionsRejectUnapprovedBundlesAndUnknownWindows() async throws {
        let fake = ActionFakeRunner()
        let executor = await actions(fake)
        for action in [
            QuickPanelDataAction.activateApplication("com.attacker.app"),
            .activateWindow(bundleID: "com.attacker.app", windowID: 1),
            .activateWindow(bundleID: "com.openai.codex", windowID: -1),
        ] {
            do {
                _ = try await executor.execute(action)
                XCTFail("Unexpected desktop action success")
            } catch let error as QuickPanelDataActionError {
                XCTAssertEqual(error, .unavailable)
            }
        }
        let calls = await fake.calls()
        XCTAssertTrue(calls.isEmpty)
    }
}
