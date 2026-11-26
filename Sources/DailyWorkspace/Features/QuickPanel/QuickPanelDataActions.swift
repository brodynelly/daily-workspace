import AppKit
import ApplicationServices
import Foundation

enum QuickPanelDataActionResult: Equatable {
    case stay
    case hide
    case workspace(String)
    case shortcut(String)
}

enum QuickPanelDataActionError: Error, Equatable, LocalizedError {
    case invalidInput
    case exited(Int32)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidInput: "Invalid panel action input"
        case .exited(let status): "Panel helper exited with status \(status)"
        case .unavailable: "Selected application or window is unavailable"
        }
    }
}

/// Executes only fixed helper commands after the caller explicitly selects a row.
@MainActor
struct QuickPanelDataActions {
    typealias Run = @Sendable (URL, [String], [String: String]) async throws -> QuickPanelCommandOutput

    private let dotfiles: URL
    private let rexExecutable: URL?
    private let activateRex: @MainActor () -> Void
    private let run: Run

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        dotfiles: URL? = nil,
        rexExecutable: URL? = QuickPanelRex.locate(),
        activateRex: @escaping @MainActor () -> Void = { QuickPanelRex.activateApp() },
        run: @escaping Run = { executable, arguments, environment in
            try await QuickPanelCommandRunner().run(
                executable: executable, arguments: arguments, environment: environment)
        }
    ) {
        self.dotfiles =
            dotfiles ?? ProcessInfo.processInfo.environment["DOTFILES_DIR"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            } ?? home.appendingPathComponent("github/dotfiles-mac", isDirectory: true)
        self.rexExecutable = rexExecutable
        self.activateRex = activateRex
        self.run = run
    }

    func execute(_ action: QuickPanelDataAction) async throws -> QuickPanelDataActionResult {
        switch action {
        case .activateApplication, .activateWindow:
            return try activateDesktop(action)
        case .focusAgent, .gotoSession:
            return try await executeSession(action)
        case .focusRexSession(let sessionID):
            return try await focusRex(sessionID)
        case .openFile, .openTarget, .closeSession:
            return try await executeOpen(action)
        case .workspaceActions, .launch, .shortcutTool:
            return try await executeWorkspace(action)
        }
    }

    private func activateDesktop(_ action: QuickPanelDataAction) throws -> QuickPanelDataActionResult {
        switch action {
        case .activateApplication(let bundleID):
            guard Self.allowedBundleIDs.contains(bundleID),
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                NSWorkspace.shared.open(url)
            else { throw QuickPanelDataActionError.unavailable }
            return .hide
        case .activateWindow(let bundleID, let windowID):
            return try activateWindow(bundleID: bundleID, windowID: windowID)
        default:
            throw QuickPanelDataActionError.unavailable
        }
    }

    private func activateWindow(bundleID: String, windowID: Int) throws -> QuickPanelDataActionResult {
        guard Self.allowedBundleIDs.contains(bundleID), windowID > 0,
            windowID <= Int(CGWindowID.max), AXIsProcessTrusted(),
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                CGWindowID(windowID)) as? [[String: Any]],
            let record = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == windowID }),
            let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
            let application = NSRunningApplication(processIdentifier: pid),
            application.bundleIdentifier == bundleID
        else { throw QuickPanelDataActionError.unavailable }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
            let axWindows = value as? [AXUIElement]
        else { throw QuickPanelDataActionError.unavailable }
        for window in axWindows {
            var number: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &number) == .success,
                (number as? NSNumber)?.intValue == windowID
            else { continue }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success,
                application.activate()
            else { throw QuickPanelDataActionError.unavailable }
            return .hide
        }
        throw QuickPanelDataActionError.unavailable
    }

    private func focusRex(_ sessionID: String) async throws -> QuickPanelDataActionResult {
        guard QuickPanelRex.validSessionID(sessionID) else { throw QuickPanelDataActionError.invalidInput }
        guard let rexExecutable else { throw QuickPanelDataActionError.unavailable }
        let output = try await run(rexExecutable, QuickPanelRex.selectArguments(sessionID: sessionID), [:])
        guard output.exitStatus == 0 else { throw QuickPanelDataActionError.exited(output.exitStatus) }
        activateRex()
        return .hide
    }

    private func executeSession(_ action: QuickPanelDataAction) async throws -> QuickPanelDataActionResult {
        switch action {
        case .focusAgent(let id):
            guard id > 0 else { throw QuickPanelDataActionError.invalidInput }
            try await command("kitty/scripts/kitty-opencode-sessions.sh", ["--focus", String(id)])
        case .gotoSession(let name):
            guard Self.validText(name) else { throw QuickPanelDataActionError.invalidInput }
            try await command("scripts/macos/mac/misc/550-skhdSession.sh", [name])
        default:
            throw QuickPanelDataActionError.invalidInput
        }
        return .hide
    }

    private func executeOpen(_ action: QuickPanelDataAction) async throws -> QuickPanelDataActionResult {
        switch action {
        case .openFile(let path):
            guard Self.validPath(path) else { throw QuickPanelDataActionError.invalidInput }
            try await command("scripts/macos/mac/misc/550-skhdSession.sh", [path])
        case .openTarget(let target):
            guard
                Self.validPath(target)
                    || (["ssh:", "tmux:"].contains {
                        target.hasPrefix($0) && Self.validText(String(target.dropFirst($0.count)))
                    })
            else { throw QuickPanelDataActionError.invalidInput }
            try await command("kitty/scripts/kitty-zoxide-session.sh", ["--open", target])
        case .closeSession(let name):
            guard Self.validText(name) else { throw QuickPanelDataActionError.invalidInput }
            try await command("scripts/macos/mac/agents/kitty_sessions.py", ["close", name])
            return .stay
        default:
            throw QuickPanelDataActionError.invalidInput
        }
        return .hide
    }

    private func executeWorkspace(_ action: QuickPanelDataAction) async throws -> QuickPanelDataActionResult {
        switch action {
        case .workspaceActions(let path):
            guard Self.validPath(path) else { throw QuickPanelDataActionError.invalidInput }
            return .workspace(path)
        case .launch(let path, let tool):
            guard Self.validPath(path), Self.validTool(tool, allowsColon: true)
            else { throw QuickPanelDataActionError.invalidInput }
            try await command("scripts/macos/mac/agents/workspace.py", ["launch", tool, path])
            return .hide
        case .shortcutTool(let id):
            guard Self.validTool(id, allowsColon: false) else { throw QuickPanelDataActionError.invalidInput }
            return .shortcut(id)
        default:
            throw QuickPanelDataActionError.invalidInput
        }
    }

    private static func validTool(_ value: String, allowsColon: Bool) -> Bool {
        !value.isEmpty && value.utf8.count <= 128
            && value.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                    || $0 == 95 || $0 == 45 || (allowsColon && $0 == 58)
            }
    }

    private func command(_ script: String, _ arguments: [String]) async throws {
        let executable = URL(
            fileURLWithPath: script.hasSuffix(".py")
                ? (FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/python3")
                    ? "/opt/homebrew/bin/python3" : "/usr/bin/python3") : "/bin/bash")
        let output = try await run(executable, [dotfiles.appendingPathComponent(script).path] + arguments, [:])
        guard output.exitStatus == 0 else { throw QuickPanelDataActionError.exited(output.exitStatus) }
    }

    private static let allowedBundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop", "com.openai.codex",
    ]

    private static func validText(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 4096
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func validPath(_ value: String) -> Bool {
        value.hasPrefix("/") && validText(value)
    }
}
