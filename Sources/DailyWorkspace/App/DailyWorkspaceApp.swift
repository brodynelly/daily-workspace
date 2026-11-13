import AppKit
import SwiftUI

@main
struct DailyWorkspaceApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var shortcut = GlobalCaptureShortcut()

    @NSApplicationDelegateAdaptor(WorkspaceAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        // Before any view resolves a type role; a no-op when the bundle has no Fonts folder (swift run).
        BundledFonts.register()
    }

    var body: some Scene {
        Window("Daily Workspace", id: WindowID.workspace) {
            RootView()
                .workspaceEnvironment(model)
                .environmentObject(shortcut)
                .frame(minWidth: 760, minHeight: 540)
                .onAppear {
                    appDelegate.configure(model: model, shortcut: shortcut, openWindow: openWindow)
                }
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            WorkspaceCommands(model: model, document: model.document, preferences: model.preferences)
        }

        Window("Capture", id: WindowID.capture) {
            CaptureForm(style: .window)
                .workspaceEnvironment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
