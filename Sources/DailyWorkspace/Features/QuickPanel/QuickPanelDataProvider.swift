import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Darwin
import Foundation

/// Listing is read-only. The controller dispatches an action only after a user selects its row.
enum QuickPanelDataAction: Equatable, Sendable {
    case focusAgent(UInt64)
    case gotoSession(String)
    case closeSession(String)
    case openFile(String)
    case openTarget(String)
    case workspaceActions(String)
    case launch(path: String, tool: String)
    case shortcutTool(String)
    case activateApplication(String)
    case activateWindow(bundleID: String, windowID: Int)
}

struct QuickPanelDataRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let group: String
    var badge = ""
    var musicArtist = ""
    var musicAlbum = ""
    var nativeRunID: String?
    var status = ""
    var keys = ""
    var keywords = ""
    var keyNames: [String] = []
    var action: QuickPanelDataAction?
    var alternate: QuickPanelDataAction?
    var remove: QuickPanelDataAction?

    static func unavailable(_ group: String, _ reason: String) -> Self {
        .init(id: "unavailable:\(group)", title: "\(group) unavailable", detail: reason, group: group)
    }
}

struct QuickPanelDataSnapshot: Sendable {
    var agents: [QuickPanelDataRow] = []
    var sessions: [QuickPanelDataRow] = []
    var files: [QuickPanelDataRow] = []
    var projects: [QuickPanelDataRow] = []
    var ssh: [QuickPanelDataRow] = []
    var desktop: [QuickPanelDataRow] = []
    var tmux: [QuickPanelDataRow] = []
    var workspaces: [QuickPanelDataRow] = []
    var shortcutTools: [QuickPanelDataRow] = []
    var shortcutEntries: [String: [QuickPanelDataRow]] = [:]
    var notices: [String] = []

    func rows(for route: QuickPanelRoute, shortcutTool: String? = nil) -> [QuickPanelDataRow] {
        switch route {
        case .home: agents + sessions + desktop
        case .agents: agents
        case .sessions: sessions
        case .files: files
        case .projects: projects
        case .ssh: ssh
        case .tmux: tmux
        case .workspaces: workspaces
        case .shortcuts: shortcutTool.map { shortcutEntries[$0] ?? [] } ?? shortcutTools
        case .attention, .system, .music, .calendar: []  // Those routes have their own source owners.
        }
    }

    func searchRows(for route: QuickPanelRoute, shortcutTool: String? = nil) -> [QuickPanelDataRow] {
        if route == .home {
            return agents + sessions + desktop + files + projects + ssh + tmux + workspaces
        }
        if route == .shortcuts && shortcutTool == nil {
            return shortcutTools
                + shortcutTools.flatMap { row in
                    guard case .shortcutTool(let id)? = row.action else { return [QuickPanelDataRow]() }
                    return shortcutEntries[id] ?? []
                }
        }
        return rows(for: route, shortcutTool: shortcutTool)
    }
}

/// A typed directory is an explicit user action, never a side effect of search.
func quickPanelTypedDirectoryRow(_ query: String, for route: QuickPanelRoute) -> QuickPanelDataRow? {
    let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard [.home, .projects, .sessions].contains(route),
        typed.hasPrefix("/") || typed.hasPrefix("~/"),
        !typed.contains(where: { "\n\r\0".contains($0) }),
        typed.utf8.count <= 4096
    else { return nil }
    let path = (typed as NSString).expandingTildeInPath
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &directory),
        directory.boolValue
    else { return nil }
    return .init(
        id: "typed-directory:\(path)", title: "New session at \(typed)",
        detail: "Open directory in Kitty", group: "Projects", action: .openTarget(path))
}

enum QuickPanelDataChange { case shortcuts, palette }
enum QuickPanelDataRefreshState { case idle, loading, ready }

/// Inject the fixed-argv runner in tests; no command is executed by constructing a row.
@MainActor
final class QuickPanelDataProvider: ObservableObject {
    typealias Run = @Sendable (URL, [String], [String: String]) async throws -> QuickPanelCommandOutput

    @Published var snapshot = QuickPanelDataSnapshot()
    @Published private(set) var refreshState: QuickPanelDataRefreshState = .idle
    private let run: Run
    private let desktopDiscovery: @MainActor () -> [QuickPanelDataRow]
    let home: URL
    let dotfiles: URL
    let bundledShortcuts: URL
    private var refreshTask: Task<QuickPanelDataSnapshot, Never>?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var watching = false
    private var watchGeneration = 0

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        dotfiles: URL? = nil,
        bundledShortcuts: URL? = nil,
        desktopDiscovery: @escaping @MainActor () -> [QuickPanelDataRow] = { QuickPanelDataProvider.desktopRows() },
        run: @escaping Run = { executable, arguments, environment in
            try await QuickPanelCommandRunner().run(
                executable: executable, arguments: arguments, environment: environment)
        }
    ) {
        self.home = home
        self.dotfiles =
            dotfiles ?? ProcessInfo.processInfo.environment["DOTFILES_DIR"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            } ?? home.appendingPathComponent("github/dotfiles-mac", isDirectory: true)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Shortcuts", isDirectory: true)
        self.bundledShortcuts =
            bundledShortcuts ?? [Bundle.main.resourceURL?.appendingPathComponent("Shortcuts"), source]
            .compactMap { $0 }.first(where: {
                FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.json").path)
            }) ?? source
        self.desktopDiscovery = desktopDiscovery
        self.run = run
    }

    /// Replaces previous pending work; cancellation also terminates in-flight helper process groups.
    func refresh() async {
        refreshTask?.cancel()
        refreshState = .loading
        let task = Task { await load() }
        refreshTask = task
        let result = await task.value
        guard !task.isCancelled else { return }
        snapshot = result
        refreshTask = nil
        refreshState = .ready
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshState = .idle
    }

    /// Actions are fetched only on drill-in, never during listing.
    func workspaceActions(for path: String) async -> [QuickPanelDataRow] {
        guard !path.isEmpty, path.utf8.count <= 4096, !path.contains(where: { "\n\r\0".contains($0) }) else {
            return [.unavailable("Launch", "Invalid workspace path")]
        }
        do {
            let data = try await command("scripts/macos/mac/agents/workspace.py", arguments: ["actions", path])
            guard let choices = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                return [.unavailable("Launch", "Invalid workspace actions response")]
            }
            let rows = choices.compactMap { value -> QuickPanelDataRow? in
                guard let choice = value as? [String: Any] else { return nil }
                guard let name = nonempty(choice, "name"), let tool = nonempty(choice, "tool"),
                    !tool.isEmpty, tool.utf8.allSatisfy({ asciiIdentifier($0) || $0 == 58 || $0 == 45 })
                else { return nil }
                return .init(
                    id: "launch:\(path):\(tool)", title: name, detail: short(path), group: "Launch",
                    action: .launch(path: path, tool: tool))
            }
            return rows.isEmpty ? [.unavailable("Launch", "No launch tools available")] : rows
        } catch {
            return [.unavailable("Launch", "Workspace actions could not be loaded")]
        }
    }

    func startWatching(onChange: @escaping @MainActor (QuickPanelDataChange) -> Void) {
        stopWatching()
        watching = true
        let generation = watchGeneration
        let shortcuts = dotfiles.appendingPathComponent("hammerspoon/shortcuts", isDirectory: true)
        let palette = dotfiles.appendingPathComponent("colorscheme/active", isDirectory: true)
        // Parents catch atomic directory replacement; children catch edits to files within each directory.
        for (directory, change, rearm) in [
            (shortcuts, QuickPanelDataChange.shortcuts, false),
            (shortcuts.deletingLastPathComponent(), .shortcuts, true),
            (palette, .palette, false),
            (palette.deletingLastPathComponent(), .palette, true),
        ] where FileManager.default.fileExists(atPath: directory.path) {
            let fd = open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete, .attrib], queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.watching, self.watchGeneration == generation else { return }
                    if case .shortcuts = change { self.reloadShortcuts() }
                    if rearm { self.startWatching(onChange: onChange) }
                    onChange(change)
                }
            }
            source.setCancelHandler { close(fd) }
            watchers.append(source)
            source.resume()
        }
    }

    func stopWatching() {
        watching = false
        watchGeneration += 1
        for watcher in watchers { watcher.cancel() }
        watchers.removeAll()
    }

    private func load() async -> QuickPanelDataSnapshot {
        async let kittyResult = readCommand("scripts/macos/mac/agents/kitty_sessions.py", arguments: ["list"])
        async let targetsResult = readCommand("kitty/scripts/kitty-zoxide-session.sh", arguments: ["--targets"])
        async let workspacesResult = readCommand("scripts/macos/mac/agents/workspace.py", arguments: ["catalog"])
        var result = QuickPanelDataSnapshot()
        result.desktop = desktopDiscovery()
        let shortcuts = shortcutRows()
        result.shortcutTools = shortcuts.0
        result.shortcutEntries = shortcuts.1
        let kitty = await kittyResult
        let targets = await targetsResult
        let workspaces = await workspacesResult
        guard !Task.isCancelled else { return result }
        switch kitty {
        case .success(let data): parseKitty(data, into: &result)
        case .failure:
            result.notices.append("Kitty sessions unavailable")
            result.agents = [.unavailable("Agents", "Kitty helper unavailable")]
            result.sessions = [.unavailable("Sessions", "Kitty helper unavailable")]
            result.files = [.unavailable("Files", "Kitty helper unavailable")]
        }
        switch targets {
        case .success(let data): parseTargets(data, into: &result)
        case .failure:
            result.notices.append("Projects, SSH and tmux unavailable")
            result.projects = [.unavailable("Projects", "Targets helper unavailable")]
            result.ssh = [.unavailable("SSH", "Targets helper unavailable")]
            result.tmux = [.unavailable("tmux", "Targets helper unavailable")]
        }
        switch workspaces {
        case .success(let data): parseWorkspaceCatalog(data, into: &result)
        case .failure:
            result.notices.append("Workspace catalog unavailable")
            result.workspaces = [.unavailable("Workspaces", "Workspace catalog helper unavailable")]
        }
        return result
    }

    private func readCommand(_ script: String, arguments: [String]) async -> Result<Data, Error> {
        do { return .success(try await command(script, arguments: arguments)) } catch { return .failure(error) }
    }

    private func command(_ script: String, arguments: [String]) async throws -> Data {
        let executable =
            script.hasSuffix(".py")
            ? URL(
                fileURLWithPath: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/python3")
                    ? "/opt/homebrew/bin/python3" : "/usr/bin/python3")
            : URL(fileURLWithPath: "/bin/bash")
        let output = try await run(executable, [dotfiles.appendingPathComponent(script).path] + arguments, [:])
        guard output.exitStatus == 0 else { throw QuickPanelDataActionError.exited(output.exitStatus) }
        return output.stdout
    }

    /// App rows need no permission. Window rows require live AX identity and on-screen WindowServer IDs.
    private static func desktopRows() -> [QuickPanelDataRow] {
        let providers = [
            ("Claude desktop", "com.anthropic.claudefordesktop"),
            ("Codex desktop", "com.openai.codex"),
        ]
        let windows =
            CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] ?? []
        var rows: [QuickPanelDataRow] = []
        for (name, bundle) in providers {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil else { continue }
            rows.append(
                .init(
                    id: "desktop:\(bundle)", title: "Open \(name)", detail: bundle,
                    group: "Desktop apps", action: .activateApplication(bundle)))
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            where AXIsProcessTrusted() {
                rows += desktopWindowRows(name: name, bundle: bundle, pid: running.processIdentifier, windows: windows)
            }
        }
        return rows
    }

    private static func desktopWindowRows(
        name: String, bundle: String, pid: pid_t, windows: [[String: Any]]
    ) -> [QuickPanelDataRow] {
        let visibleIDs = Set(
            windows.compactMap { window -> Int? in
                guard let owner = window[kCGWindowOwnerPID as String] as? Int32, owner == pid,
                    (window[kCGWindowLayer as String] as? Int) == 0
                else { return nil }
                return window[kCGWindowNumber as String] as? Int
            })
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.12)
        var windowList: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowList) == .success,
            let accessibilityWindows = windowList as? [AXUIElement]
        else { return [] }
        var rows: [QuickPanelDataRow] = []
        for window in accessibilityWindows {
            AXUIElementSetMessagingTimeout(window, 0.12)
            var numberValue: CFTypeRef?
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &numberValue) == .success,
                let number = (numberValue as? NSNumber)?.intValue, visibleIDs.contains(number),
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                let title = titleValue as? String, !title.isEmpty
            else { continue }
            rows.append(
                .init(
                    id: "desktop:\(bundle):\(number)", title: "\(name) · \(title)",
                    detail: "Desktop window", group: "Desktop apps",
                    action: .activateWindow(bundleID: bundle, windowID: number)))
        }
        return rows
    }
}

func nonempty(_ object: [String: Any], _ field: String) -> String? {
    guard let value = object[field] as? String, !value.isEmpty else { return nil }
    return value
}

func keyString(_ value: Any?) -> String {
    guard let chords = value as? [[String]] else { return "" }
    return chords.map { $0.joined(separator: " ") }.joined(separator: " / ")
}

func shortcutSearchKeys(_ value: Any?) -> (String, [String]) {
    guard let chords = value as? [[String]] else { return ("", []) }
    var words: [String] = []
    var names: [String] = []
    let aliases: [Character: String] = [
        "⌃": "ctrl control", "⌥": "alt option opt", "⇧": "shift",
        "⌘": "cmd command", "↵": "return enter", "↩": "return enter",
        "⇥": "tab", "␣": "space leader", "⌫": "backspace", "⌦": "delete",
        "↑": "up", "↓": "down", "←": "left", "→": "right",
    ]
    for step in chords.flatMap({ $0 }) {
        let lower = step.lowercased()
        words.append(lower)
        for char in lower {
            if let alias = aliases[char] { words.append(alias) }
        }
        let name = String(lower.drop(while: { "⌃⌥⇧⌘".contains($0) }))
        words.append(name)
        names.append(name)
    }
    return (words.joined(separator: " "), names)
}
