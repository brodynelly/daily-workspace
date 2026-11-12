import SwiftUI

/// Menu-bar extra: capture from anywhere without bringing the workspace forward. A native menu, so it keeps
/// the system's menu styling; items carry the same symbols as the command registry.
struct CaptureMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var shortcut: GlobalCaptureShortcut

    var body: some View {
        Button {
            openWindow(id: WindowID.capture)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label(AppCommand.captureWindow.title, systemImage: AppCommand.captureWindow.symbol)
        }
        Button {
            openWindow(id: WindowID.workspace)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Open Workspace", systemImage: "macwindow")
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
