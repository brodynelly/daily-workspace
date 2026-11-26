import Combine
import DailyCore
import Foundation

/// Resolves configurable, non-menu workspace shortcuts. Menu and button shortcuts keep native macOS handling.
@MainActor
final class MainWindowShortcutRouter: ObservableObject {
    enum Outcome: Equatable {
        case unhandled
        case waiting
        case action(String)
    }

    @Published private(set) var pendingHint: String?
    private var first: ShortcutStroke?
    private var deadline: TimeInterval = 0
    private var timeoutTask: Task<Void, Never>?
    private static let chordTimeout: TimeInterval = 1.5
    private static let actionIDs =
        AppCommand.paletteCommands.map(\.id) + [
            AppCommand.commandPalette.id, "quickSearch", "keyboardHelp", "assistant.panel", "sidebar.toggle",
            "calendar.previousWeek", "calendar.nextWeek", "assistant.stop",
        ] + AppSection.allCases.map { "goChord.\($0.rawValue)" }

    func reset() {
        first = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        deadline = 0
        pendingHint = nil
    }

    func accept(
        _ stroke: ShortcutStroke, preferences: Preferences, activeSection: AppSection? = nil,
        assistantPanelVisible: Bool = false, at now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Outcome {
        if let first, now <= deadline {
            for id in Self.actionIDs {
                guard
                    let binding = activeBinding(
                        for: id, preferences: preferences, section: activeSection,
                        assistantPanelVisible: assistantPanelVisible),
                    binding.strokes.count == 2, binding.strokes[0] == first,
                    binding.strokes[1] == stroke
                else { continue }
                reset()
                return .action(id)
            }
        }
        reset()
        for id in Self.actionIDs {
            guard
                let binding = activeBinding(
                    for: id, preferences: preferences, section: activeSection,
                    assistantPanelVisible: assistantPanelVisible),
                binding.strokes.count == 2, binding.strokes[0] == stroke
            else { continue }
            first = stroke
            deadline = now + Self.chordTimeout
            pendingHint = id.hasPrefix("goChord.") ? "Go to…" : "Next shortcut key…"
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.chordTimeout))
                guard !Task.isCancelled else { return }
                self?.reset()
            }
            return .waiting
        }
        for id in Self.actionIDs {
            guard
                let binding = activeBinding(
                    for: id, preferences: preferences, section: activeSection,
                    assistantPanelVisible: assistantPanelVisible),
                binding.strokes.count == 1, binding.strokes[0] == stroke,
                binding.menuShortcut == nil || id == "quickSearch" || id == "keyboardHelp"
                    || id == "assistant.panel" || id == "assistant.stop"
            else { continue }
            return .action(id)
        }
        return .unhandled
    }
    private func activeBinding(
        for id: String, preferences: Preferences, section: AppSection?, assistantPanelVisible: Bool
    ) -> ShortcutBinding? {
        switch KeyboardShortcutCatalog.context(for: id) {
        case .calendar where section != .calendar: return nil
        case .assistant where section != .assistant && !assistantPanelVisible: return nil
        default: return KeyboardShortcutCatalog.binding(for: id, preferences: preferences)
        }
    }

}
