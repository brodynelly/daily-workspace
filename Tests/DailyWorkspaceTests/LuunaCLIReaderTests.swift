import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

private final class LuunaCommandSpy: LuunaCommandRunning, @unchecked Sendable {
    struct Call {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    let reply: @Sendable ([String]) async throws -> QuickPanelCommandOutput

    init(reply: @escaping @Sendable ([String]) async throws -> QuickPanelCommandOutput) {
        self.reply = reply
    }

    var calls: [Call] { lock.withLock { recorded } }

    func run(executable: URL, arguments: [String], environment: [String: String]) async throws
        -> QuickPanelCommandOutput
    {
        lock.withLock { recorded.append(Call(executable: executable, arguments: arguments, environment: environment)) }
        return try await reply(arguments)
    }
}

final class LuunaCLIReaderTests: XCTestCase {
    private let executable = URL(fileURLWithPath: "/Users/fixture/.local/bin/lu")

    private struct CLIErrorCase {
        let message: String
        let exitStatus: Int32
        let expected: LuunaReadFailure
    }

    func testFourReadOnlyCommandsUseExactArgvAndCurrentConnectionOnly() async throws {
        let spy = LuunaCommandSpy { argv in
            let data: Data
            switch argv {
            case ["health", "--json"]: data = LuunaFixtures.health
            case ["projects", "--json"]: data = LuunaFixtures.projects
            case ["project", "a b/c", "--json"]: data = LuunaFixtures.project
            case ["components", "daily-workspace", "--json"]: data = LuunaFixtures.components
            default: throw QuickPanelCommandError.invalidArguments
            }
            return QuickPanelCommandOutput(stdout: data, exitStatus: 0)
        }
        let reader = LuunaCLIReader(executable: executable, runner: spy)
        let connection = LuunaConnection(
            origin: try LuunaOrigin(validating: "http://[::1]:5151"), token: "keychain-token")
        let health = try await reader.health(connection)
        let projects = try await reader.projects(connection)
        let project = try await reader.project("a b/c", connection)
        let components = try await reader.components("daily-workspace", connection)
        XCTAssertEqual(health, LuunaFixtures.healthValue)
        XCTAssertEqual(projects, LuunaFixtures.projectsValue)
        XCTAssertEqual(project, LuunaFixtures.projectValue)
        XCTAssertEqual(components, LuunaFixtures.componentsValue)
        XCTAssertEqual(
            spy.calls.map(\.arguments),
            [
                ["health", "--json"], ["projects", "--json"],
                ["project", "a b/c", "--json"], ["components", "daily-workspace", "--json"],
            ])
        for call in spy.calls {
            XCTAssertEqual(call.executable, executable)
            XCTAssertTrue(call.executable.isFileURL)
            XCTAssertEqual(
                call.environment,
                [
                    "LUUNA_URL": "http://[::1]:5151", "LUUNA_API_TOKEN": "keychain-token",
                ])
            XCTAssertFalse(call.arguments.joined().contains("keychain-token"))
        }
        XCTAssertEqual(LuunaCLIReader.timeout, 10)
        XCTAssertEqual(LuunaCLIReader.outputLimit, 2 * 1024 * 1024)
    }

    func testNativeWorkCommandsPreserveUnknownColumnsAndTicketStatus() async throws {
        let board = Data(
            #"{"columns":[{"column":{"id":"future_qa","title":"Future QA"},"cards":[{"column":"future_qa","kind":"ticket","project_id":"p","title":"Open work","ticket_id":"t","run_id":"done","state":"completed"}]}]}"#
                .utf8)
        let ticketJSON = #"{"id":"t","project_id":"p","revision":2,"title":"Open work","status":"open"}"#
        let ticket = Data(ticketJSON.utf8)
        let home = Data(#"{"projects":[],"blockers":[]}"#.utf8)
        let spy = LuunaCommandSpy { argv in
            switch argv {
            case ["board", "--project", "p", "--json"]: return QuickPanelCommandOutput(stdout: board, exitStatus: 0)
            case ["tickets", "p", "--json"]:
                return QuickPanelCommandOutput(
                    stdout: Data("[\(ticketJSON)]".utf8), exitStatus: 0)
            case ["show-ticket", "t", "--json"]: return QuickPanelCommandOutput(stdout: ticket, exitStatus: 0)
            case ["home", "--project", "p", "--json"]: return QuickPanelCommandOutput(stdout: home, exitStatus: 0)
            case ["home", "--json"]: return QuickPanelCommandOutput(stdout: home, exitStatus: 0)
            default: throw QuickPanelCommandError.invalidArguments
            }
        }
        let reader = LuunaCLIReader(executable: executable, runner: spy)
        let connection = LuunaConnection(origin: .standard, token: "current-token")
        let observedBoard = try await reader.board("p", connection)
        XCTAssertEqual(observedBoard.columns.first?.column.id, "future_qa")
        XCTAssertEqual(observedBoard.columns.first?.cards.first?.state?.rawValue, "completed")
        let tickets = try await reader.tickets("p", connection)
        let detail = try await reader.showTicket("t", connection)
        let observedHome = try await reader.home("p", connection)
        let observedAllProjectHome = try await reader.homeAll(connection)
        XCTAssertEqual(tickets.first?.status?.rawValue, "open")
        XCTAssertEqual(detail.status?.rawValue, "open")
        XCTAssertEqual(observedHome.projects.count, 0)
        XCTAssertEqual(observedAllProjectHome.projects.count, 0)
        XCTAssertEqual(
            spy.calls.map(\.environment),
            Array(
                repeating: [
                    "LUUNA_URL": LuunaOrigin.standard.description, "LUUNA_API_TOKEN": "current-token",
                ], count: 5))
        XCTAssertEqual(
            spy.calls.map(\.arguments),
            [
                ["board", "--project", "p", "--json"], ["tickets", "p", "--json"],
                ["show-ticket", "t", "--json"], ["home", "--project", "p", "--json"], ["home", "--json"],
            ])
        await expectFailure(.unauthorized) {
            try await reader.board("p", LuunaConnection(origin: .standard, token: " "))
        }
        await expectFailure(.unauthorized) {
            try await reader.homeAll(LuunaConnection(origin: .standard, token: " "))
        }
        XCTAssertEqual(spy.calls.count, 5)
    }
}

extension LuunaCLIReaderTests {
    func testRunListAndDetailUseReadOnlyBoundedArgvAndSeparateMissingRecord() async throws {
        let run = #"{"id":"r-1","project_id":"p","state":"completed","metadata":{"ticket_id":"t"}}"#
        let spy = LuunaCommandSpy { argv in
            switch argv {
            case ["runs", "--project", "p", "--json"]:
                return QuickPanelCommandOutput(stdout: Data("[\(run)]".utf8), exitStatus: 0)
            case ["run", "r-1", "--json"]:
                return QuickPanelCommandOutput(stdout: Data(run.utf8), exitStatus: 0)
            default: throw QuickPanelCommandError.invalidArguments
            }
        }
        let reader = LuunaCLIReader(executable: executable, runner: spy)
        let list = try await reader.runs("p", .fixture)
        let detail = try await reader.run("r-1", .fixture)
        XCTAssertEqual(list, [detail])
        XCTAssertEqual(detail.state.rawValue, "completed")
        XCTAssertEqual(detail.ticketID, "t")
        XCTAssertEqual(
            spy.calls.map(\.arguments),
            [
                ["runs", "--project", "p", "--json"], ["run", "r-1", "--json"],
            ])
        XCTAssertEqual(
            LuunaCLIReader.classify(
                Data(#"{"error":"Run inspection refused: The runtime no longer has this record."}"#.utf8),
                exitStatus: 1, command: "run"),
            .refused(LuunaRefusal(status: 404, reason: nil)))
    }

    func testMalformedRunDetailReturnsPartialWithoutLeakingChildOutput() async {
        let spy = LuunaCommandSpy { _ in
            QuickPanelCommandOutput(
                stdout: Data(#"{"id":"r","project_id":"p","state":{"secret":"never-display"}}"#.utf8),
                exitStatus: 0)
        }
        let reader = LuunaCLIReader(executable: executable, runner: spy)
        await expectFailure(.undecodable) { try await reader.run("r", .fixture) }
    }

    func testUnknownNativeAdapterStatusIsKeptVerbatim() async throws {
        let bytes = Data(
            #"{"enabled":true,"adapters":[{"name":"missions","status":"awaiting-review","backend_status":"new-state"}]}"#
                .utf8)
        let spy = LuunaCommandSpy { _ in QuickPanelCommandOutput(stdout: bytes, exitStatus: 0) }
        let components = try await LuunaCLIReader(executable: executable, runner: spy)
            .components("daily-workspace", .fixture)
        XCTAssertEqual(components.adapters?.first?.status?.rawValue, "awaiting-review")
        XCTAssertEqual(components.adapters?.first?.backendStatus?.rawValue, "new-state")
    }

    func testMissingTokenAndUnsupportedOriginNeverSpawn() async throws {
        let spy = LuunaCommandSpy { _ in throw QuickPanelCommandError.invalidArguments }
        let reader = LuunaCLIReader(executable: executable, runner: spy)
        await expectFailure(.unauthorized) {
            try await reader.health(LuunaConnection(origin: .standard, token: "  "))
        }
        // A LuunaConnection can only contain a validated origin; the parser refuses nonloopback
        // before any connection or child process can be constructed.
        XCTAssertThrowsError(try LuunaOrigin(validating: "http://example.com"))
        XCTAssertThrowsError(try LuunaOrigin(validating: "http://127.0.0.1:4242/other"))
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testCLIErrorShapesClassifyWithoutShowingChildOrToken() async throws {
        let token = "secret-token-not-for-errors"
        let cases: [CLIErrorCase] = [
            .init(
                message: "Project listing refused: The service rejected this token. Reconnect using its current token.",
                exitStatus: 1, expected: .unauthorized),
            .init(
                message: "Project listing refused: The runtime denied this action.",
                exitStatus: 1, expected: .unauthorized),
            .init(
                message: "Connection refused: The runtime did not answer. Start the service.",
                exitStatus: 1, expected: .unavailable(.cannotConnect)),
            .init(
                message: "Project listing refused: The runtime no longer has this record. Refresh the panel.",
                exitStatus: 1, expected: .unsupported),
            .init(
                message: "Project listing refused: Runtime request failed (HTTP 501).",
                exitStatus: 1, expected: .unsupported),
            .init(
                message: "Project listing refused: Runtime request failed (HTTP 422). \(token)",
                exitStatus: 1, expected: .refused(LuunaRefusal(status: 422, reason: nil))),
            .init(
                message: "Project listing refused: The runtime reported an internal error (HTTP 500).",
                exitStatus: 1, expected: .unavailable(.serverError(status: 500))),
            .init(
                message: "the CLI doesn't know this option \(token)",
                exitStatus: 2, expected: .unsupported),
        ]
        for testCase in cases {
            let bytes = try JSONSerialization.data(withJSONObject: ["error": testCase.message])
            let spy = LuunaCommandSpy { _ in QuickPanelCommandOutput(stdout: bytes, exitStatus: testCase.exitStatus) }
            let reader = LuunaCLIReader(executable: executable, runner: spy)
            await expectFailure(testCase.expected) { try await reader.projects(.fixture) }
            let classified = LuunaCLIReader.classify(bytes, exitStatus: testCase.exitStatus, command: "projects")
            XCTAssertFalse(String(describing: classified).contains(token))
        }
        let missing = LuunaCLIReader.classify(
            Data(#"{"error":"Project inspection refused: The runtime no longer has this record."}"#.utf8),
            exitStatus: 1, command: "project")
        XCTAssertEqual(missing, .refused(LuunaRefusal(status: 404, reason: nil)))
    }

    func testCLIStatusStatesKeepRefusalSeparateFromSourceUnavailability() throws {
        let cases: [(String, LuunaReadFailure)] = [
            ("Runtime request failed (HTTP 429).", .unavailable(.busy)),
            ("Runtime request failed (HTTP 503).", .unavailable(.serverError(status: 503))),
            ("The runtime is shutting down.", .unavailable(.shuttingDown("Runtime is shutting down."))),
            ("Runtime request failed (HTTP 409).", .refused(LuunaRefusal(status: 409, reason: nil))),
            ("The action was refused.", .refused(LuunaRefusal(status: 0, reason: nil))),
        ]
        for (message, expected) in cases {
            let bytes = try JSONSerialization.data(withJSONObject: ["error": message])
            XCTAssertEqual(LuunaCLIReader.classify(bytes, exitStatus: 1, command: "projects"), expected)
        }
        XCTAssertEqual(
            LuunaCLIReader.classify(Data(), exitStatus: 1, command: "projects"),
            .unavailable(.cannotConnect))
    }

    func testStderrOnlyUnauthorizedStatusesAreSafeAndOtherStderrIsPrivate() async throws {
        let token = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        let connection = LuunaConnection(origin: .standard, token: token)
        for status in [401, 403] {
            let stderr = Data("Luuna: Local service returned HTTP \(status). token=\(token)".utf8)
            let output = QuickPanelCommandOutput(stdout: Data(), exitStatus: 1, stderr: stderr)
            let spy = LuunaCommandSpy { _ in output }
            await expectFailure(.unauthorized) {
                try await LuunaCLIReader(executable: executable, runner: spy).projects(connection)
            }
            XCTAssertFalse(String(describing: output).contains(token))
            XCTAssertFalse(String(reflecting: output).contains(token))
        }
        for diagnostic in [
            "Luuna: Invalid token \(token). Secret syntax details",
            "Luuna: Token too short: \(token)",
            "Luuna: Local service returned HTTP 4012: \(token)",
        ] {
            let stderr = Data(diagnostic.utf8)
            let malformedSpy = LuunaCommandSpy { _ in
                QuickPanelCommandOutput(stdout: Data(), exitStatus: 1, stderr: stderr)
            }
            await expectFailure(.unavailable(.cannotConnect)) {
                try await LuunaCLIReader(executable: executable, runner: malformedSpy).projects(connection)
            }
        }
        XCTAssertFalse(LuunaReadFailure.unauthorized.localizedDescription.contains(token))
        let wrongExitSpy = LuunaCommandSpy { _ in
            QuickPanelCommandOutput(stdout: Data(), exitStatus: 2, stderr: Data("HTTP 401".utf8))
        }
        await expectFailure(.unsupported) {
            try await LuunaCLIReader(executable: executable, runner: wrongExitSpy).projects(connection)
        }
    }

    func testBadJSONAndBoundedRunnerErrorsHaveTruthfulStates() async {
        let bad = LuunaCommandSpy { _ in QuickPanelCommandOutput(stdout: Data("[]".utf8), exitStatus: 0) }
        await expectFailure(.undecodable) {
            try await LuunaCLIReader(executable: executable, runner: bad).health(.fixture)
        }
        let cases: [(QuickPanelCommandError, LuunaReadFailure)] = [
            (.timedOut, .unavailable(.timedOut)),
            (.outputTooLarge, .undecodable),
            (.launchFailed(2), .unsupported),
            (.ioFailed, .unavailable(.cannotConnect)),
        ]
        for (commandError, expected) in cases {
            let spy = LuunaCommandSpy { _ in throw commandError }
            await expectFailure(expected) {
                try await LuunaCLIReader(executable: executable, runner: spy).health(.fixture)
            }
        }
    }

    func testCancellationIsNotTurnedIntoSourceFailure() async throws {
        let gate = LuunaGate()
        let spy = LuunaCommandSpy { _ in
            await gate.wait()
            return QuickPanelCommandOutput(stdout: LuunaFixtures.health, exitStatus: 0)
        }
        let reader = LuunaCLIReader(executable: executable, runner: spy)
        let task = Task { try await reader.health(.fixture) }
        try await gate.waitForArrival()
        task.cancel()
        gate.open()
        do {
            _ = try await task.value
            XCTFail("Cancelled read must not publish a source observation")
        } catch is CancellationError {
            XCTAssertEqual(spy.calls.count, 1)
        }
    }
}

extension LuunaCLIReaderTests {
    private func expectFailure<Value>(
        _ expected: LuunaReadFailure, _ operation: () async throws -> Value,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LuunaReadFailure, expected, file: file, line: line)
        }
    }
}
