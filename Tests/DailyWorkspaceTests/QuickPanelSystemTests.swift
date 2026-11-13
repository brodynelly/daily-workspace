import Foundation
import XCTest

@testable import DailyWorkspace

@MainActor
private final class FakeSystemActionExecutor: QuickPanelSystemActionExecuting {
    enum Call: Equatable {
        case open(String)
        case run(String, [String])
        case bluetoothLookup
        case confirmRestart
    }

    var calls: [Call] = []
    var confirmation = false
    var bluetooth: URL? = URL(fileURLWithPath: "/opt/homebrew/bin/blueutil")
    var openError: Error?
    var runErrors: [Int: Error] = [:]
    private var runCount = 0

    func openApplication(bundleIdentifier: String) async throws {
        calls.append(.open(bundleIdentifier))
        if let openError { throw openError }
    }

    func run(executable: URL, arguments: [String]) async throws {
        calls.append(.run(executable.path, arguments))
        runCount += 1
        if let error = runErrors[runCount] { throw error }
    }

    func bluetoothExecutable() -> URL? {
        calls.append(.bluetoothLookup)
        return bluetooth
    }

    func confirmRestart() -> Bool {
        calls.append(.confirmRestart)
        return confirmation
    }
}

@MainActor
final class QuickPanelSystemTests: XCTestCase {
    func testSystemApplicationsUseBundleIdentifiers() async {
        let executor = FakeSystemActionExecutor()
        let actions = QuickPanelSystemActions(executor: executor)

        let preferences = await actions.perform(.preferences)
        let activity = await actions.perform(.activityMonitor)
        XCTAssertEqual(preferences, .completed)
        XCTAssertEqual(activity, .completed)
        XCTAssertEqual(
            executor.calls,
            [.open("com.apple.systempreferences"), .open("com.apple.ActivityMonitor")]
        )
    }

    func testDisplaySleepUsesFixedHelperAndArgument() async {
        let executor = FakeSystemActionExecutor()

        let result = await QuickPanelSystemActions(executor: executor).perform(.lockScreen)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(executor.calls, [.run("/usr/bin/pmset", ["displaysleepnow"])])
    }

    func testMissingBluetoothHelperIsUnavailableWithoutAttemptingPowerChange() async {
        let executor = FakeSystemActionExecutor()
        executor.bluetooth = nil

        let result = await QuickPanelSystemActions(executor: executor).perform(.bluetoothRestart)

        guard case .unavailable(let message) = result else {
            return XCTFail("Expected an unavailable state, got \(result)")
        }
        XCTAssertTrue(message.contains("blueutil"))
        XCTAssertEqual(executor.calls, [.bluetoothLookup])
    }

    func testBluetoothRestartTurnsPowerOffThenBackOn() async {
        let executor = FakeSystemActionExecutor()

        let result = await QuickPanelSystemActions(executor: executor).perform(.bluetoothRestart)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(
            executor.calls,
            [
                .bluetoothLookup,
                .run("/opt/homebrew/bin/blueutil", ["--power", "0"]),
                .run("/opt/homebrew/bin/blueutil", ["--power", "1"]),
            ]
        )
    }

    func testBluetoothPermissionDenialDoesNotAttemptToTurnPowerOn() async {
        let executor = FakeSystemActionExecutor()
        executor.runErrors[1] = NSError(domain: NSPOSIXErrorDomain, code: 1)

        let result = await QuickPanelSystemActions(executor: executor).perform(.bluetoothRestart)

        guard case .permissionDenied(let message) = result else {
            return XCTFail("Expected a permission-denied state, got \(result)")
        }
        XCTAssertTrue(message.contains("System Settings"))
        XCTAssertEqual(executor.calls.count, 2)
    }

    func testBluetoothPowerOnFailureWarnsThatBluetoothMayRemainOff() async {
        let executor = FakeSystemActionExecutor()
        executor.runErrors[2] = TestFailure("Bluetooth permission denied")

        let result = await QuickPanelSystemActions(executor: executor).perform(.bluetoothRestart)

        guard case .failed(let message) = result else {
            return XCTFail("Expected a failure state, got \(result)")
        }
        XCTAssertTrue(message.contains("Bluetooth may be off"))
        XCTAssertTrue(message.contains("permission denied"))
        XCTAssertEqual(executor.calls.count, 3)
    }

    func testBluetoothPowerOnPermissionDenialIncludesRecoveryWarning() async {
        let executor = FakeSystemActionExecutor()
        executor.runErrors[2] = NSError(domain: NSPOSIXErrorDomain, code: 13)

        let result = await QuickPanelSystemActions(executor: executor).perform(.bluetoothRestart)

        guard case .permissionDenied(let message) = result else {
            return XCTFail("Expected a permission-denied state, got \(result)")
        }
        XCTAssertTrue(message.contains("Bluetooth may be off"))
        XCTAssertEqual(executor.calls.count, 3)
    }

    func testCancellationCannotRunRestartAppleEvent() async {
        let executor = FakeSystemActionExecutor()

        let result = await QuickPanelSystemActions(executor: executor).perform(.restart)
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(executor.calls, [.confirmRestart])
    }

    func testConfirmedRestartExecutesOnlyAfterConfirmation() async {
        let executor = FakeSystemActionExecutor()
        executor.confirmation = true

        let result = await QuickPanelSystemActions(executor: executor).perform(.restart)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(
            executor.calls,
            [
                .confirmRestart,
                .run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to restart"]),
            ]
        )
    }

    func testRestartPermissionDenialIsVisibleAfterConfirmation() async {
        let executor = FakeSystemActionExecutor()
        executor.confirmation = true
        executor.runErrors[1] = NSError(domain: NSOSStatusErrorDomain, code: -1743)

        let result = await QuickPanelSystemActions(executor: executor).perform(.restart)

        guard case .permissionDenied(let message) = result else {
            return XCTFail("Expected a permission-denied state, got \(result)")
        }
        XCTAssertTrue(message.contains("permissions"))
        XCTAssertEqual(executor.calls.count, 2)
    }

    func testHelperFailureIsNotSilentlyReportedAsSuccess() async {
        let executor = FakeSystemActionExecutor()
        executor.runErrors[1] = TestFailure("display unavailable")

        let result = await QuickPanelSystemActions(executor: executor).perform(.lockScreen)

        guard case .failed(let message) = result else {
            return XCTFail("Expected a failure state, got \(result)")
        }
        XCTAssertTrue(message.contains("display unavailable"))
        XCTAssertEqual(result.errorMessage, message)
    }

    func testApplicationUnavailableIsDistinctFromPermissionDenied() async {
        let executor = FakeSystemActionExecutor()
        executor.openError = NSError(domain: NSPOSIXErrorDomain, code: 13)
        let denied = await QuickPanelSystemActions(executor: executor).perform(.preferences)
        guard case .permissionDenied = denied else {
            return XCTFail("Expected a permission-denied state, got \(denied)")
        }
    }
}
