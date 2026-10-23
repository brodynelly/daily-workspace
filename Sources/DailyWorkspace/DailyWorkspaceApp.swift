import SwiftUI
import AppKit

@main
struct DailyWorkspaceApp: App {
    @StateObject private var state = AppState()
    @StateObject private var shortcut = GlobalCaptureShortcut()

    @NSApplicationDelegateAdaptor(WorkspaceAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Daily Workspace", id: "workspace") {
            RootView()
                .environmentObject(state)
                .environmentObject(shortcut)
                .frame(minWidth: 760, minHeight: 540)
                .onAppear { appDelegate.state = state }
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick Capture…") { state.showQuickCapture = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Capture Window…") { shortcut.onCapture?() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Open Today's Note") {
                    state.section = .notes
                    state.openToday()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Note") { state.saveNow() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!state.canSave)
                Button("Reveal Note in Finder") {
                    if let url = state.noteURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state.noteURL == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Search Actions…") { state.showCommandPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Choose Vault…") { state.chooseVault() }
            }
            CommandMenu("Go") {
                ForEach(Array(AppState.Section.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) { state.section = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        Window("Quick Capture", id: "capture") {
            QuickCaptureSheet()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(WorkspaceTheme.coral)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra("Daily Workspace", systemImage: "sun.max") {
            CaptureMenu(shortcut: shortcut).environmentObject(state)
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(WorkspaceTheme.coral)
        }
    }
}
