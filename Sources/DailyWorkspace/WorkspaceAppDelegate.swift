import AppKit

/// AppKit owns process activation and the synchronous quit decision only.
/// All document state and persistence remain in AppState.
@MainActor
final class WorkspaceAppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state, !state.prepareToQuit() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Your note needs attention before quitting"
        alert.informativeText = "Resolve the save error or file conflict in Notes, then quit again. Your edits are still open."
        alert.addButton(withTitle: "Return to Notes")
        alert.runModal()
        state.section = .notes
        sender.activate(ignoringOtherApps: true)
        return .terminateCancel
    }
}
