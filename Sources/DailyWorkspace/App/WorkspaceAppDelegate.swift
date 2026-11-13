import AppKit
import Combine
import SwiftUI

/// AppKit owns the panel and process lifecycle; document state stays in the stores owned by `AppModel`.
@MainActor
final class WorkspaceAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    let quickPanel = QuickPanelController()
    private lazy var integrations = QuickPanelIntegrations(
        colorschemeURL: URL(fileURLWithPath: (panelConfiguration.dotfiles as NSString).expandingTildeInPath)
            .appendingPathComponent("colorscheme/active/active-colorscheme.sh")
    )
    private var captureMenu: CaptureMenu?
    private var controlServer: QuickPanelControlServer?
    private var panelConfiguration = QuickPanelControlConfiguration()
    private var configurationLoaded = false
    private var serviceErrors: [String] = []
    private var integrationPreferences: Preferences?
    private var integrationObservation: AnyCancellable?
    private weak var shortcut: GlobalCaptureShortcut?
    func configure(model: AppModel, shortcut: GlobalCaptureShortcut, openWindow: OpenWindowAction) {
        self.model = model
        self.shortcut = shortcut
        loadPanelConfigurationIfNeeded()
        captureMenu?.observe(shortcut)
        quickPanel.configure(model: model, configuration: panelConfiguration)
        observeIntegrations(model.preferences)
        quickPanel.openWorkspace = { [weak model] section in
            guard let model else { return }
            model.navigation.section = section
            openWindow(id: WindowID.workspace)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func shouldActivateOnLaunch(arguments: [String]) -> Bool {
        !arguments.contains("--background-control")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if Self.shouldActivateOnLaunch(arguments: ProcessInfo.processInfo.arguments) {
            NSApp.activate(ignoringOtherApps: true)
        }
        captureMenu = CaptureMenu(panel: quickPanel)
        loadPanelConfigurationIfNeeded()
        if let shortcut { captureMenu?.observe(shortcut) }
        captureMenu?.reportServiceError(serviceErrors.isEmpty ? nil : serviceErrors.joined(separator: " "))
        integrations.onClipboardFeedback = { visible in
            Self.setClipboardFeedback(visible: visible)
        }
        if let preferences = model?.preferences { observeIntegrations(preferences) }
        integrations.start()
        do {
            let server = try QuickPanelControlServer()
            server.start { [weak self] action in
                guard let self else { return ["ok": false, "error": "Service unavailable"] }
                if action == .clipboard, !integrations.flashClipboard() {
                    return ["ok": false, "error": "Clipboard feedback is disabled in Settings."]
                }
                if action == .paletteChanged { integrations.refreshPalette() }
                return quickPanel.handleControlAction(action)
            }
            controlServer = server
        } catch {
            reportServiceError("Control service: \(error.localizedDescription)")
            Log.app.error("Quick panel control service could not start: \(Log.code(error), privacy: .public)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controlServer?.stop()
        controlServer = nil
        integrations.stop()
        integrationObservation = nil
    }

    private func loadPanelConfigurationIfNeeded() {
        guard !configurationLoaded else { return }
        configurationLoaded = true
        let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
        let explicitURL: URL?
        if let index = arguments.firstIndex(of: "--config") {
            guard arguments.indices.contains(index + 1) else {
                reportServiceError("Quick panel configuration: --config requires a path.")
                return
            }
            explicitURL = URL(fileURLWithPath: arguments[index + 1])
        } else {
            explicitURL = nil
        }
        do {
            panelConfiguration = try QuickPanelControlConfiguration.load(at: explicitURL)
        } catch {
            reportServiceError("Quick panel configuration: \(error.localizedDescription)")
            Log.app.error("Quick panel configuration could not be read: \(Log.code(error), privacy: .public)")
        }
    }

    private func observeIntegrations(_ preferences: Preferences) {
        guard integrationPreferences !== preferences else { return }
        integrationObservation = nil
        integrationPreferences = preferences
        applyIntegrationConsent(
            clipboard: preferences.quickPanelClipboardEnabled,
            border: preferences.quickPanelTerminalBorderEnabled)
        integrationObservation = preferences.$quickPanelClipboardEnabled
            .combineLatest(preferences.$quickPanelTerminalBorderEnabled)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] clipboard, border in
                MainActor.assumeIsolated {
                    self?.applyIntegrationConsent(clipboard: clipboard, border: border)
                }
            }
    }

    private func applyIntegrationConsent(clipboard: Bool, border: Bool) {
        integrations.setEnabled(
            clipboard: clipboard && panelConfiguration.clipboardFeedback,
            border: border && panelConfiguration.terminalBorder)
    }

    private func reportServiceError(_ error: String) {
        serviceErrors.append(error)
        captureMenu?.reportServiceError(serviceErrors.joined(separator: " "))
    }

    private static func setClipboardFeedback(visible: Bool) {
        let path = "/opt/homebrew/bin/sketchybar"
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--set", "clipboard.feedback", visible ? "drawing=on" : "drawing=off"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !model.prepareToQuit() else { return .terminateNow }
        Log.app.notice("Quit deferred: the open note needs attention")
        let alert = NSAlert()
        alert.messageText = "Your note needs attention before quitting"
        alert.informativeText =
            "Resolve the save error or file conflict in Notes, then quit again. Your edits are still open."
        alert.addButton(withTitle: "Return to Notes")
        alert.runModal()
        quickPanel.openWorkspace?(.notes)
        sender.activate(ignoringOtherApps: true)
        return .terminateCancel
    }
}
