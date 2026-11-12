import SwiftUI

/// Menu-bar extra: capture from anywhere without bringing the workspace forward.
struct CaptureMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var shortcut: GlobalCaptureShortcut

    var body: some View {
        Button(AppCommand.captureWindow.title) {
            openWindow(id: WindowID.capture)
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Open Workspace") {
            openWindow(id: WindowID.workspace)
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        if shortcut.error != nil {
            Text("Global capture shortcut unavailable")
        } else {
            Text("Capture from anywhere: " + shortcut.label)
        }
        SettingsLink()
        Divider()
        Button("Quit Daily Workspace") { NSApp.terminate(nil) }
    }
}
