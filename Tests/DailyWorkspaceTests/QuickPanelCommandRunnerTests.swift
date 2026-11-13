import Darwin
import Foundation
import XCTest

@testable import DailyWorkspace

final class QuickPanelCommandRunnerTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    private func expectError(
        _ expected: QuickPanelCommandError, file: StaticString = #filePath, line: UInt = #line,
        _ operation: () async throws -> QuickPanelCommandOutput
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? QuickPanelCommandError, expected, file: file, line: line)
        }
    }

    func testArgumentsArePassedVerbatimAndEnvironmentPrefixesHomebrew() async throws {
        let payload = "$(id); `whoami` ' \"\nhello"
        let output = try await QuickPanelCommandRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", payload])
        XCTAssertEqual(try XCTUnwrap(String(data: output.stdout, encoding: .utf8)), payload)
        XCTAssertEqual(output.exitStatus, 0)

        let path = try await QuickPanelCommandRunner().run(
            executable: shell, arguments: ["-c", "printf '%s' \"$PATH\""],
            environment: ["PATH": "/custom/commands"])
        XCTAssertEqual(
            try XCTUnwrap(String(data: path.stdout, encoding: .utf8)),
            "/opt/homebrew/bin:/usr/local/bin:/custom/commands")
    }

    func testChildReceivesOnlyMinimalEnvironmentAndExplicitCredentials() async throws {
        let secretKey = "QAP_AMBIENT_SECRET_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let secret = "ambient-private-value"
        XCTAssertEqual(setenv(secretKey, secret, 1), 0)
        defer { _ = unsetenv(secretKey) }
        let output = try await QuickPanelCommandRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [],
            environment: ["LUUNA_API_TOKEN": "explicit-credential"])
        let text = try XCTUnwrap(String(data: output.stdout, encoding: .utf8))
        XCTAssertFalse(text.contains(secretKey))
        XCTAssertFalse(text.contains(secret))
        XCTAssertTrue(text.contains("LUUNA_API_TOKEN=explicit-credential"))
        XCTAssertTrue(text.contains("HOME="))
        XCTAssertTrue(text.contains("PATH=/opt/homebrew/bin:/usr/local/bin:"))
    }

    func testStdinIsNullAndBothPipesAreConsumed() async throws {
        let output = try await QuickPanelCommandRunner().run(
            executable: shell,
            arguments: ["-c", "head -c 65536 /dev/zero >&2; read line || printf 'stdin-closed'"])
        XCTAssertEqual(try XCTUnwrap(String(data: output.stdout, encoding: .utf8)), "stdin-closed")
    }

    func testExitStatusRetainsStdoutWithoutLeakingStderrOrArguments() async throws {
        let secret = "private-token-value"
        let json = #"{"error":"unavailable"}"#
        let output = try await QuickPanelCommandRunner().run(
            executable: shell,
            arguments: ["-c", "printf '%s' \"$1\"; printf '%s' \"$2\" >&2; exit 23", "sh", json, secret])
        XCTAssertEqual(output.exitStatus, 23)
        XCTAssertEqual(try XCTUnwrap(String(data: output.stdout, encoding: .utf8)), json)
        XCTAssertFalse(String(reflecting: output).contains(secret))
        XCTAssertFalse(output.hasUnauthorizedHTTPStatusInStderr)
        XCTAssertFalse(String(describing: output).contains(secret))
        XCTAssertEqual(Mirror(reflecting: output).children.compactMap(\.label), ["exitStatus"])
        await expectError(.launchFailed(2)) {
            try await QuickPanelCommandRunner().run(
                executable: URL(fileURLWithPath: "/nonexistent/secret-helper"), arguments: [secret])
        }
        XCTAssertFalse(QuickPanelCommandError.launchFailed(2).localizedDescription.contains(secret))
    }

    func testStderrIsPrivatelyBoundedAndOnlyRecognizesFixedUnauthorizedStatuses() async throws {
        let output = try await QuickPanelCommandRunner(outputLimit: 16 * 1024).run(
            executable: shell,
            arguments: ["-c", "printf 'HTTP 403 private-token' >&2; exit 1"])
        XCTAssertTrue(output.hasUnauthorizedHTTPStatusInStderr)
        XCTAssertFalse(String(describing: output).contains("private-token"))
        XCTAssertFalse(String(reflecting: output).contains("private-token"))

        let oversized = try await QuickPanelCommandRunner(outputLimit: 16 * 1024).run(
            executable: shell,
            arguments: ["-c", "head -c 5000 /dev/zero | tr '\\000' 'x' >&2; printf 'HTTP 401' >&2; exit 1"])
        XCTAssertFalse(oversized.hasUnauthorizedHTTPStatusInStderr)
    }

    func testExitedLeaderKillsDescendantsThatClosedOutputPipes() async throws {
        let marker = try temporaryMarker()
        defer { try? FileManager.default.removeItem(at: marker.deletingLastPathComponent()) }
        let script = "( sleep 0.5; echo survived > \"$1\" ) </dev/null >/dev/null 2>&1 & exit 0"
        let output = try await QuickPanelCommandRunner(timeout: 2).run(
            executable: shell, arguments: ["-c", script, "sh", marker.path])
        XCTAssertEqual(output.exitStatus, 0)
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testDeadlineKillsDescendantsKeepingOutputPipeOpen() async throws {
        let marker = try temporaryMarker()
        defer { try? FileManager.default.removeItem(at: marker.deletingLastPathComponent()) }
        // The shell exits; its child inherits the pipe, so a runner watching only the leader would hang.
        let script = "( sleep 0.5; echo survived > \"$1\" ) & exit 0"
        await expectError(.timedOut) {
            try await QuickPanelCommandRunner(timeout: 0.15).run(
                executable: shell, arguments: ["-c", script, "sh", marker.path])
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCombinedOutputCapKillsDescendants() async throws {
        let marker = try temporaryMarker()
        defer { try? FileManager.default.removeItem(at: marker.deletingLastPathComponent()) }
        let script = "( sleep 0.5; echo survived > \"$1\" ) & printf 1234; printf 5678 >&2; wait"
        await expectError(.outputTooLarge) {
            try await QuickPanelCommandRunner(timeout: 2, outputLimit: 7).run(
                executable: shell, arguments: ["-c", script, "sh", marker.path])
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCancellationKillsDescendantsAndReturnsCancellation() async throws {
        let marker = try temporaryMarker()
        defer { try? FileManager.default.removeItem(at: marker.deletingLastPathComponent()) }
        let task = Task {
            try await QuickPanelCommandRunner(timeout: 3).run(
                executable: shell,
                arguments: ["-c", "( sleep 0.5; echo survived > \"$1\" ) & wait", "sh", marker.path])
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Cancellation must wait for group kill and leader reap.
        } catch {
            XCTFail("Expected CancellationError, got \(type(of: error))")
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testDoesNotBlockMainActor() async throws {
        let runner = QuickPanelCommandRunner(timeout: 1)
        let task = Task { @MainActor in
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["0.2"])
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        let started = Date()
        await MainActor.run { XCTAssertLessThan(Date().timeIntervalSince(started), 0.1) }
        _ = try await task.value
    }

    private func temporaryMarker() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        // The disposable directory is outside every vault. It exists only for descendant-liveness assertions.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("descendant-survived")
    }
}
