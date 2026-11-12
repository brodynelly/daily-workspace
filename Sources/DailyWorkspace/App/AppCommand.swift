import AppKit
import SwiftUI

/// Every app command, in one registry. The menu bar and the command palette are built from it,
/// so titles, symbols and shortcuts cannot drift apart.
enum AppCommand: Hashable, Identifiable {
    case quickCapture
    case captureWindow
    case openTodayNote
    case saveNote
    case revealNote
    case commandPalette
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
        case .chooseVault: return "folder.badge.plus"
        case .settings: return "gearshape"
        case .go(let section): return section.symbol
        }
    }

    var shortcut: KeyboardShortcut? {
        switch self {
        case .quickCapture: return KeyboardShortcut("n", modifiers: .command)
        case .captureWindow: return KeyboardShortcut("n", modifiers: [.command, .option])
        case .openTodayNote: return KeyboardShortcut("t", modifiers: [.command, .shift])
        case .saveNote: return KeyboardShortcut("s", modifiers: .command)
        case .revealNote: return KeyboardShortcut("r", modifiers: [.command, .shift])
        case .commandPalette: return KeyboardShortcut("k", modifiers: .command)
        case .settings: return KeyboardShortcut(",", modifiers: .command)
        case .chooseVault: return nil
        case .go(let section): return section.shortcut
        }
    }

    /// Shortcut in macOS menu notation, e.g. "⇧⌘T".
    var shortcutLabel: String {
        guard let shortcut else { return "" }
        let modifiers = shortcut.modifiers
        var label = ""
        if modifiers.contains(.control) { label += "⌃" }
        if modifiers.contains(.option) { label += "⌥" }
        if modifiers.contains(.shift) { label += "⇧" }
        if modifiers.contains(.command) { label += "⌘" }
        return label + String(shortcut.key.character).uppercased()
    }

    /// What the palette offers: every screen, then every action except the palette itself.
    static let paletteCommands: [AppCommand] =
        AppSection.allCases.map(AppCommand.go) + [
            .quickCapture, .captureWindow, .openTodayNote, .saveNote, .revealNote, .chooseVault, .settings,
        ]
}

/// Performs commands. Needs the SwiftUI window actions, so it is created inside views and commands.
@MainActor
struct CommandRunner {
    let model: AppModel
    let openWindow: OpenWindowAction
    var openSettings: (() -> Void)?

    func isEnabled(_ command: AppCommand) -> Bool {
        switch command {
        case .saveNote: return model.document.canSave
        case .revealNote: return model.document.url != nil
        case .settings: return openSettings != nil
        default: return true
        }
    }

    func run(_ command: AppCommand) {
        switch command {
        case .quickCapture: model.navigation.showQuickCapture = true
        case .captureWindow:
            openWindow(id: WindowID.capture)
            NSApp.activate(ignoringOtherApps: true)
        case .openTodayNote: model.openToday(navigate: true)
        case .saveNote: model.document.saveNow()
        case .revealNote:
            if let url = model.document.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .commandPalette: model.navigation.showCommandPalette = true
        case .chooseVault: model.chooseVault()
        case .settings: openSettings?()
        case .go(let section): model.navigation.section = section
        }
    }
}

/// Menu-bar commands built from the registry. Settings (⌘,) is supplied by the system menu.
struct WorkspaceCommands: Commands {
    let model: AppModel
    @ObservedObject var document: NoteDocument
    @Environment(\.openWindow) private var openWindow

    private var runner: CommandRunner { CommandRunner(model: model, openWindow: openWindow) }

    var body: some Commands {
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
        SidebarCommands()
        CommandMenu("Go") {
            ForEach(AppSection.allCases) { item(.go($0)) }
        }
    }

    private func item(_ command: AppCommand) -> some View {
        Button(command.title) { runner.run(command) }
            .keyboardShortcut(command.shortcut)
            .disabled(!runner.isEnabled(command))
    }
}
