import SwiftUI

/// Sidebar screens. Order defines the sidebar, the Go menu and the ⌘1…⌘6 shortcuts.
/// Each screen opens with its title and one sentence that says what it is for (`description`).
enum AppSection: String, CaseIterable, Identifiable {
    case today, projects, openLoops, notes, calendar, assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .projects: return "Projects"
        case .openLoops: return "Open Loops"
        case .notes: return "Notes"
        case .calendar: return "Calendar"
        case .assistant: return "Assistant"
        }
    }

    /// The one sentence under the screen's title.
    var description: String {
        switch self {
        case .today:
            return "Today's agenda, what is due today and today's note, with capture close at hand."
        case .projects:
            return "Each project's purpose, decisions and latest restart record, read from the vault."
        case .openLoops:
            return "Every open item across its owners, shown with its source and the owner's own status."
        case .notes:
            return "Write in your vault's Markdown notes, and search their names and contents."
        case .calendar:
            return "One day of Apple Calendar events, to review and edit."
        case .assistant:
            return "Ask about your notes, open loops, projects and calendar; read-only, it cites what it read."
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .projects: return "folder"
        case .openLoops: return "circle.dashed"
        case .notes: return "doc.text"
        case .calendar: return "calendar"
        case .assistant: return "bubble.left.and.bubble.right"
        }
    }

}

/// Window identifiers shared by scenes and the commands that open them.
enum WindowID {
    static let workspace = "workspace"
    static let capture = "capture"
}

/// What the Notes screen shows: the open note, or vault search.
enum NotesMode: String, CaseIterable {
    case editor, search

    var title: String {
        switch self {
        case .editor: return "Editor"
        case .search: return "Search"
        }
    }
}

/// Transient, source-cited text awaiting an explicit Notes review. No destination is model-selected.
struct AssistantNoteDraft {
    var text: String
    let paths: [String]
}

/// The active screen stays selected while Settings is open so Back returns to it.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var section: AppSection = .today {
        didSet { showingSettings = false }
    }
    @Published var showingSettings = false
    @Published var settingsTab: SettingsTab = .vault
    @Published var showingAssistantPanel = false
    @Published var assistantDraft = ""
    @Published var notesMode: NotesMode = .editor
    @Published var reviewedAssistantNote: AssistantNoteDraft?
    @Published var showQuickCapture = false
    @Published var showCommandPalette = false

    func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        showingSettings = true
    }

    func closeSettings() { showingSettings = false }
}
