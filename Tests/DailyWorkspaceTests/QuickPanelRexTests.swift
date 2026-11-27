import Foundation
import XCTest

@testable import DailyWorkspace

private actor RexFakeRunner {
    var recorded: [(executable: String, arguments: [String])] = []
    var output = QuickPanelCommandOutput(stdout: Data(), exitStatus: 0)

    func run(_ executable: URL, _ arguments: [String]) -> QuickPanelCommandOutput {
        recorded.append((executable.path, arguments))
        return output
    }

    func set(_ text: String, status: Int32 = 0) { output = .init(stdout: Data(text.utf8), exitStatus: status) }
    func arguments() -> [[String]] { recorded.map(\.arguments) }
    func executables() -> [String] { recorded.map(\.executable) }
}

@MainActor
final class QuickPanelRexTests: XCTestCase {
    private let rex = URL(fileURLWithPath: "/tmp/fake-rex/rex")
    private let listing = """
        {"sessions": [
          {"session_id": "session:01a216bf-1575-7f26-abc8-fd9dfd3b2448", "label": "dotfiles"},
          {"session_id": "session:01a216c4-49b9-72e6-a0a4-8d1b57ba9519", "label": ""},
          {"session_id": "not-a-session", "label": "bad"}
        ]}
        """

    @MainActor
    private func provider(_ fake: RexFakeRunner, rex: URL?) -> QuickPanelDataProvider {
        let root = URL(fileURLWithPath: "/tmp/rex-panel-dotfiles")
        return QuickPanelDataProvider(
            home: root, dotfiles: root, bundledShortcuts: root, desktopDiscovery: { [] }, rexExecutable: rex,
            run: { executable, arguments, _ in
                guard executable.lastPathComponent == "rex" else { throw QuickPanelCommandError.ioFailed }
                return await fake.run(executable, arguments)
            })
    }

    func testRexSessionsFormTheirOwnSectionBesideTmuxAndInHomeSearch() async throws {
        let fake = RexFakeRunner()
        await fake.set(listing)
        let data = await provider(fake, rex: rex)
        await data.refresh()
        let snapshot = await data.snapshot

        XCTAssertEqual(snapshot.rex.map(\.title), ["dotfiles", "ba9519"])
        XCTAssertEqual(snapshot.rex.map(\.group), ["Rex", "Rex"])
        XCTAssertEqual(snapshot.rex.first?.action, .focusRexSession("session:01a216bf-1575-7f26-abc8-fd9dfd3b2448"))
        XCTAssertTrue(snapshot.rows(for: .tmux).contains { $0.group == "Rex" })
        XCTAssertTrue(snapshot.rows(for: .tmux).contains { $0.group == "tmux" }, "tmux keeps its own section")
        XCTAssertTrue(snapshot.searchRows(for: .home).contains { $0.id.hasPrefix("rex:") })

        let calls = await fake.arguments()
        XCTAssertEqual(calls, [["--autostart=false", "--timeout", "5s", "ls", "--json"]])
        let executables = await fake.executables()
        XCTAssertEqual(executables, [rex.path])
    }

    func testRexUnavailableStatesNeverHideTmuxOrStartAServer() async throws {
        let fake = RexFakeRunner()
        await fake.set("", status: 4)
        var data = await provider(fake, rex: rex)
        await data.refresh()
        var snapshot = await data.snapshot
        XCTAssertEqual(snapshot.rex.map(\.title), ["Rex unavailable"])
        XCTAssertEqual(snapshot.rex.first?.detail, "Rex server is not running")
        XCTAssertNil(snapshot.rex.first?.action)

        await fake.set("{broken")
        await data.refresh()
        snapshot = await data.snapshot
        XCTAssertEqual(snapshot.rex.first?.detail, "Invalid Rex sessions response")

        await fake.set("{\"sessions\": []}")
        await data.refresh()
        snapshot = await data.snapshot
        XCTAssertTrue(snapshot.rex.isEmpty)

        data = await provider(fake, rex: nil)
        await data.refresh()
        snapshot = await data.snapshot
        XCTAssertEqual(snapshot.rex.first?.detail, "Rex is not installed")
        XCTAssertNil(snapshot.rex.first?.action)
        let calls = await fake.arguments()
        XCTAssertTrue(calls.allSatisfy { $0.first == "--autostart=false" })
    }

    func testSelectingARexRowUsesSessionSelectWithFixedArgv() async throws {
        let fake = RexFakeRunner()
        let executor = await QuickPanelDataActions(
            dotfiles: URL(fileURLWithPath: "/tmp/rex-panel-dotfiles"), rexExecutable: rex, activateRex: {},
            run: { executable, arguments, _ in
                await fake.run(executable, arguments)
            })
        let id = "session:01a216bf-1575-7f26-abc8-fd9dfd3b2448"
        let result = try await executor.execute(.focusRexSession(id))
        XCTAssertEqual(result, .hide)
        let calls = await fake.arguments()
        XCTAssertEqual(
            calls, [["--autostart=false", "--timeout", "5s", "do", "session.select", "session_id=\(id)"]])

        for invalid in ["session:", "session:XYZ", "session:01a2 --autostart=true", "window:01a2"] {
            do {
                _ = try await executor.execute(.focusRexSession(invalid))
                XCTFail("\(invalid) should be refused")
            } catch {
                XCTAssertEqual(error as? QuickPanelDataActionError, .invalidInput)
            }
        }
        await fake.set("", status: 1)
        do {
            _ = try await executor.execute(.focusRexSession(id))
            XCTFail("A failed select must surface")
        } catch {
            XCTAssertEqual(error as? QuickPanelDataActionError, .exited(1))
        }
    }
}
