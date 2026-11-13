import AppKit
import Combine
import ServiceManagement

/// Native status item: a normal click toggles the panel, Option-click opens its menu.
@MainActor
final class CaptureMenu: NSObject {
    private let panel: QuickPanelController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var shortcutError: String?
    private var serviceError: String?
    private var shortcutObservation: AnyCancellable?

    init(panel: QuickPanelController) {
        self.panel = panel
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked(_:))
        panel.onErrorChange = { [weak self] _ in self?.updateBadge() }
        updateBadge()
    }

    func observe(_ shortcut: GlobalCaptureShortcut) {
        shortcutObservation = shortcut.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                MainActor.assumeIsolated {
                    self?.shortcutError = error
                    self?.updateBadge()
                }
            }
    }

    func reportServiceError(_ error: String?) {
        serviceError = error
        updateBadge()
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggle(.home)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Daily Workspace")
        for (title, route) in [
            ("Open", QuickPanelRoute.home),
            ("Agent sessions", .agents),
            ("Keyboard shortcuts", .shortcuts),
            ("Turbo Music", .music),
            ("System", .system),
        ] {
            let item = menu.addItem(withTitle: title, action: #selector(openRoute(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = route
        }
        menu.addItem(.separator())
        let accessibility = menu.addItem(
            withTitle: "Accessibility Settings…", action: #selector(openAccessibilitySettings(_:)), keyEquivalent: ""
        )
        accessibility.target = self
        let login = menu.addItem(withTitle: "Start at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Daily Workspace", action: #selector(quit(_:)), keyEquivalent: "")
        quit.target = self
        return menu
    }

    @objc private func openRoute(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? QuickPanelRoute else { return }
        panel.show(route)
    }

    @objc private func openAccessibilitySettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLogin(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            panel.reportError(nil)
        } catch {
            panel.reportError(error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = "Could not change Start at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func updateBadge() {
        let error = serviceError ?? panel.error ?? shortcutError
        statusItem.button?.title = error == nil ? "▣" : "▣ !"
        statusItem.button?.toolTip = error.map { "Daily Workspace: \($0)" } ?? "Daily Workspace quick panel"
    }
}
