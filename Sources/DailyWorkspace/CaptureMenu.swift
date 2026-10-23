import SwiftUI

struct CaptureMenu: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var shortcut: GlobalCaptureShortcut
    var body: some View {
        Button("Quick Capture…") {
            openWindow(id: "capture")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Open Workspace") {
            openWindow(id: "workspace")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Text("Capture: " + shortcut.label)
        if shortcut.error != nil { Text("Shortcut unavailable") }
        SettingsLink()
        Divider()
        Button("Quit Daily Workspace") { NSApp.terminate(nil) }
    }
}
