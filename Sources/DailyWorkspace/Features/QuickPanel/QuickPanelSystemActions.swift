import AppKit
import Foundation

/// The five actions in QAP's System view. The lock action sleeps the display; it does not lock the session.
enum QuickPanelSystemAction: String, CaseIterable, Identifiable {
    case preferences
    case activityMonitor
    case lockScreen
    case bluetoothRestart
    case restart

    var id: Self { self }

    var title: String {
        switch self {
        case .preferences: "Preferences"
        case .activityMonitor: "Activity"
        case .lockScreen: "Lock Screen"
        case .bluetoothRestart: "BT Restart"
        case .restart: "Restart"
        }
    }

    var detail: String {
        switch self {
        case .preferences: "System Settings"
        case .activityMonitor: "Activity Monitor"
        case .lockScreen: "Put the display to sleep"
        case .bluetoothRestart: "Turn Bluetooth off and back on"
        case .restart: "Ask before restarting this Mac"
        }
    }
}

/// The panel can display unavailable, permission and execution failures separately from a user cancellation.
enum QuickPanelSystemActionResult: Equatable {
    case completed
    case cancelled
    case unavailable(String)
    case permissionDenied(String)
    case failed(String)

    var errorMessage: String? {
        switch self {
        case .completed, .cancelled: nil
        case .unavailable(let message), .permissionDenied(let message), .failed(let message): message
        }
    }
}

/// Injectable boundary: tests never launch system helpers, toggle Bluetooth or send restart Apple Events.
@MainActor
protocol QuickPanelSystemActionExecuting {
    func openApplication(bundleIdentifier: String) async throws
    func run(executable: URL, arguments: [String]) async throws
    func bluetoothExecutable() -> URL?
    func confirmRestart() -> Bool
}

private enum QuickPanelSystemActionFailure: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}

@MainActor
struct NativeQuickPanelSystemActionExecutor: QuickPanelSystemActionExecuting {
    private let runner = QuickPanelCommandRunner()

    func openApplication(bundleIdentifier: String) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw QuickPanelSystemActionFailure.unavailable("Application unavailable: \(bundleIdentifier).")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func run(executable: URL, arguments: [String]) async throws {
        let output = try await runner.run(executable: executable, arguments: arguments)
        guard output.exitStatus == 0 else { throw QuickPanelCommandError.exited(output.exitStatus) }
    }

    func bluetoothExecutable() -> URL? {
        ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    func confirmRestart() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Restart this Mac?"
        alert.informativeText = "Save your work before restarting."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Restart")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

@MainActor
struct QuickPanelSystemActions {
    private let executor: any QuickPanelSystemActionExecuting

    init(executor: (any QuickPanelSystemActionExecuting)? = nil) {
        self.executor = executor ?? NativeQuickPanelSystemActionExecutor()
    }

    func perform(_ action: QuickPanelSystemAction) async -> QuickPanelSystemActionResult {
        do {
            return try await execute(action)
        } catch let error as QuickPanelSystemActionFailure {
            return .unavailable(error.localizedDescription)
        } catch {
            return Self.failure(action: action, error: error)
        }
    }

    private func execute(_ action: QuickPanelSystemAction) async throws -> QuickPanelSystemActionResult {
        switch action {
        case .preferences:
            try await executor.openApplication(bundleIdentifier: "com.apple.systempreferences")
        case .activityMonitor:
            try await executor.openApplication(bundleIdentifier: "com.apple.ActivityMonitor")
        case .lockScreen:
            try await executor.run(executable: URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["displaysleepnow"])
        case .bluetoothRestart:
            return try await restartBluetooth()
        case .restart:
            // Never send the Apple Event except after an affirmative native macOS confirmation.
            guard executor.confirmRestart() else { return .cancelled }
            try await executor.run(
                executable: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", "tell application \"System Events\" to restart"]
            )
        }
        return .completed
    }

    private func restartBluetooth() async throws -> QuickPanelSystemActionResult {
        guard let executable = executor.bluetoothExecutable() else {
            return .unavailable("BT Restart requires blueutil in /opt/homebrew/bin or /usr/local/bin.")
        }
        try await executor.run(executable: executable, arguments: ["--power", "0"])
        do {
            try await executor.run(executable: executable, arguments: ["--power", "1"])
            return .completed
        } catch {
            let message = "Bluetooth may be off. Turn it back on in System Settings. \(error.localizedDescription)"
            return Self.permissionDenied(error) ? .permissionDenied(message) : .failed(message)
        }
    }

    private static func failure(action: QuickPanelSystemAction, error: Error) -> QuickPanelSystemActionResult {
        let diagnostic = "\(action.title) failed: \(error.localizedDescription)"
        if permissionDenied(error) {
            let permission =
                action == .bluetoothRestart
                ? "Check blueutil's Bluetooth permission in System Settings."
                : "Check this app's macOS permissions in System Settings."
            return .permissionDenied("\(diagnostic) \(permission)")
        }
        switch action {
        case .bluetoothRestart:
            return .failed("\(diagnostic) Check blueutil's Bluetooth permission in System Settings.")
        case .restart:
            return .failed("\(diagnostic) Check Automation permission for System Events in System Settings.")
        default:
            return .failed(diagnostic)
        }
    }

    private static func permissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSOSStatusErrorDomain && nsError.code == -1743)
            || (nsError.domain == NSPOSIXErrorDomain && (nsError.code == 1 || nsError.code == 13))
    }
}
