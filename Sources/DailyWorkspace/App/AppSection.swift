import SwiftUI

/// Sidebar screens. Order defines the sidebar, the Go menu and the ⌘1…⌘7 shortcuts.
enum AppSection: String, CaseIterable, Identifiable {
    case today, notes, tasks, calendar, search, reminders, chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .notes: return "Notes"
        case .tasks: return "Tasks"
        case .calendar: return "Calendar"
        case .search: return "Search"
        case .reminders: return "Reminders"
        case .chat: return "AI Chat"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .notes: return "doc.text"
        case .tasks: return "checklist"
        case .calendar: return "calendar"
        case .search: return "magnifyingglass"
        case .reminders: return "list.bullet.circle"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }

    /// ⌘ plus the 1-based sidebar position.
    var shortcut: KeyboardShortcut {
        let position = Self.allCases.firstIndex(of: self)! + 1
        return KeyboardShortcut(KeyEquivalent(Character(String(position))), modifiers: .command)
    }
}

/// Window identifiers shared by scenes and the commands that open them.
enum WindowID {
    static let workspace = "workspace"
    static let capture = "capture"
}

/// Which screen and which modal surfaces are showing.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var section: AppSection = .today
    @Published var showQuickCapture = false
    @Published var showCommandPalette = false
}
