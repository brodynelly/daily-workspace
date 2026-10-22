import SwiftUI
import AppKit

@main
struct DailyWorkspaceApp: App {
    @StateObject private var state = AppState()

    init() {
        // Lets `swift run` show a normal window with a menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("Daily Workspace") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 580)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick Capture…") { state.showQuickCapture = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open Today's Note") {
                    state.section = .notes
                    state.openToday()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Note") { state.saveNow() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu("Go") {
                ForEach(Array(AppState.Section.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) { state.section = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
