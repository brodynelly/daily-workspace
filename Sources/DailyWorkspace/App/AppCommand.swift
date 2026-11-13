import AppKit
import SwiftUI

/// Every app command in one registry. The menu bar and command palette share these IDs with
/// KeyboardShortcutCatalog so user bindings and displayed keys stay in sync.
enum AppCommand: Hashable, Identifiable {
    case quickCapture
    case captureWindow
    case openTodayNote
    case saveNote
    case revealNote
    case commandPalette
    case searchNotes
    case chooseVault
    case settings
    case go(AppSection)

    var id: String {
        if case .go(let section) = self { return "go." + section.rawValue }
        return String(describing: self)
    }

    var title: String {
        switch self {
        case .quickCapture: return "Quick Capture…"
        case .captureWindow: return "Capture Window…"
        case .openTodayNote: return "Open Today's Note"
        case .saveNote: return "Save Note"
        case .revealNote: return "Reveal Note in Finder"
        case .commandPalette: return "Command Palette…"
        case .searchNotes: return "Search Notes…"
        case .chooseVault: return "Choose Vault…"
        case .settings: return "Settings…"
        case .go(let section): return section.title
        }
    }

    /// Palette rows read "Go to Notes" so screens are distinguishable from actions.
    var paletteTitle: String {
        if case .go(let section) = self { return "Go to \(section.title)" }
        return title
    }

    var symbol: String {
        switch self {
        case .quickCapture: return "square.and.pencil"
        case .captureWindow: return "macwindow.badge.plus"
        case .openTodayNote: return "doc.text"
        case .saveNote: return "square.and.arrow.down"
        case .revealNote: return "folder"
        case .commandPalette: return "command"
        case .searchNotes: return "magnifyingglass"
        case .chooseVault: return "folder.badge.plus"
        case .settings: return "gearshape"
        case .go(let section): return section.symbol
        }
    }

    @MainActor func configuredShortcut(using preferences: Preferences) -> KeyboardShortcut? {
        KeyboardShortcutCatalog.binding(for: id, preferences: preferences)?.menuShortcut
    }

    @MainActor func configuredLabel(using preferences: Preferences) -> String {
        guard let binding = KeyboardShortcutCatalog.binding(for: id, preferences: preferences) else { return "" }
        return KeyboardShortcutCatalog.label(for: binding)
    }

    /// What the palette offers: every screen, then every action except the palette itself. Vault search
    /// lives in Notes and stays one command away here.
    static let paletteCommands: [AppCommand] =
        AppSection.allCases.map(AppCommand.go) + [
            .searchNotes, .quickCapture, .captureWindow, .openTodayNote, .saveNote, .revealNote, .chooseVault,
            .settings,
        ]
}

/// Performs commands and brings the single workspace window forward for navigation.
@MainActor
struct CommandRunner {
    let model: AppModel
    let openWindow: OpenWindowAction

    func isEnabled(_ command: AppCommand) -> Bool {
        switch command {
        case .saveNote: return model.document.canSave
        case .revealNote: return model.document.url != nil
        default: return true
        }
    }

    func run(_ command: AppCommand) {
        switch command {
        case .quickCapture, .commandPalette, .searchNotes, .go:
            navigate(command)
            focusWorkspace()
        case .captureWindow:
            openWindow(id: WindowID.capture)
            NSApp.activate(ignoringOtherApps: true)
        case .openTodayNote:
            model.openToday(navigate: true)
            focusWorkspace()
        case .saveNote: model.document.saveNow()
        case .revealNote:
            if let url = model.document.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .chooseVault: model.chooseVault()
        case .settings:
            model.navigation.showSettings()
            focusWorkspace()
        }
    }

    private func focusWorkspace() {
        guard let app = NSApp, app.isRunning else { return }
        openWindow(id: WindowID.workspace)
        app.activate(ignoringOtherApps: true)
    }

    /// Commands that only change what the window shows.
    private func navigate(_ command: AppCommand) {
        let navigation = model.navigation
        switch command {
        case .quickCapture: navigation.showQuickCapture = true
        case .commandPalette: navigation.showCommandPalette = true
        case .searchNotes:
            navigation.notesMode = .search
            navigation.section = .notes
        case .go(let section): navigation.section = section
        default: break
        }
    }
}

/// Menu-bar commands built from the registry, including the standard ⌘, Settings item.
struct WorkspaceCommands: Commands {
    let model: AppModel
    @ObservedObject var document: NoteDocument
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var preferences: Preferences

    private var runner: CommandRunner { CommandRunner(model: model, openWindow: openWindow) }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            item(.settings)
        }
        CommandGroup(replacing: .newItem) {
            item(.quickCapture)
            item(.captureWindow)
            item(.openTodayNote)
            Divider()
            item(.chooseVault)
        }
        CommandGroup(replacing: .saveItem) {
            item(.saveNote)
            item(.revealNote)
        }
        CommandGroup(after: .toolbar) {
            item(.commandPalette)
        }
        CommandMenu("Go") {
            ForEach(AppSection.allCases) { item(.go($0)) }
            Divider()
            item(.searchNotes)
        }
    }

    private func item(_ command: AppCommand) -> some View {
        Button(command.title) { runner.run(command) }
            .keyboardShortcut(command.configuredShortcut(using: preferences))
            .disabled(preferences.isRecordingShortcut || !runner.isEnabled(command))
    }
}
