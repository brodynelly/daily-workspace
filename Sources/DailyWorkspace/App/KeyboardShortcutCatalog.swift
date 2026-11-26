import DailyCore
import Foundation

/// A shortcut belongs to one focused surface; workspace shortcuts are also active in its feature views.
enum ShortcutContext: String {
    case workspace, calendar, assistant, quickPanel, global

    func overlaps(_ other: Self) -> Bool {
        self == other || self == .global || other == .global
            || (self == .workspace && (other == .calendar || other == .assistant))
            || (other == .workspace && (self == .calendar || self == .assistant))
    }
}

struct KeyboardShortcutDefinition: Identifiable {
    let id: String
    let title: String
    let group: String
    let context: ShortcutContext
    let defaultBinding: ShortcutBinding?
}

enum ShortcutBindingError: Error, Equatable, LocalizedError {
    case unknownAction
    case invalidStroke
    case reservedStroke
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .unknownAction: return "This shortcut action is no longer available."
        case .invalidStroke: return "Use one or two supported keys with valid modifiers."
        case .reservedStroke: return "That shortcut is reserved by macOS or text editing."
        case .conflict(let title): return "Conflicts with \(title). Clear or rebind that shortcut first."
        }
    }
}

/// Stable IDs, user-visible defaults and conflict checks for all shortcut surfaces.
@MainActor
enum KeyboardShortcutCatalog {
    private static func stroke(_ key: String, _ modifiers: ShortcutModifiers = []) -> ShortcutStroke {
        ShortcutStroke(key, modifiers: modifiers)
    }

    private static func one(_ key: String, _ modifiers: ShortcutModifiers = []) -> ShortcutBinding {
        ShortcutBinding(stroke(key, modifiers))
    }

    private static func go(_ key: String) -> ShortcutBinding {
        ShortcutBinding(stroke("g"), stroke(key))
    }

    private static func define(
        _ id: String, _ title: String, _ group: String, _ context: ShortcutContext, _ binding: ShortcutBinding?
    ) -> KeyboardShortcutDefinition {
        .init(id: id, title: title, group: group, context: context, defaultBinding: binding)
    }

    static let definitions: [KeyboardShortcutDefinition] = [
        define("go.today", "Go to Today", "Navigation", .workspace, one("1", .command)),
        define("go.projects", "Go to Projects", "Navigation", .workspace, one("2", .command)),
        define("go.openLoops", "Go to Open Loops", "Navigation", .workspace, one("3", .command)),
        define("go.notes", "Go to Notes", "Navigation", .workspace, one("4", .command)),
        define("go.calendar", "Go to Calendar", "Navigation", .workspace, one("5", .command)),
        define("go.assistant", "Go to Assistant", "Navigation", .workspace, one("6", .command)),
        define("goChord.today", "Go to Today (G then T)", "Navigation", .workspace, go("t")),
        define("goChord.projects", "Go to Projects (G then P)", "Navigation", .workspace, go("p")),
        define("goChord.openLoops", "Go to Open Loops (G then O)", "Navigation", .workspace, go("o")),
        define("goChord.notes", "Go to Notes (G then N)", "Navigation", .workspace, go("n")),
        define("goChord.calendar", "Go to Calendar (G then C)", "Navigation", .workspace, go("c")),
        define("goChord.assistant", "Go to Assistant (G then A)", "Navigation", .workspace, go("a")),
        define("sidebar.toggle", "Toggle Sidebar", "Navigation", .workspace, one("s", [.control, .command])),
        define("quickSearch", "Quick Search Notes", "Navigation", .workspace, one("/")),
        define("keyboardHelp", "Keyboard Shortcuts", "Navigation", .workspace, one("f1")),
        define("assistant.panel", "Toggle AI Sidebar", "Navigation", .workspace, one("/", .shift)),
        define("quickCapture", "Quick Capture", "Actions", .workspace, one("n", .command)),
        define("captureWindow", "Capture Window", "Actions", .workspace, one("n", [.command, .option])),
        define("openTodayNote", "Open Today's Note", "Actions", .workspace, one("t", [.command, .shift])),
        define("saveNote", "Save Note", "Actions", .workspace, one("s", .command)),
        define("revealNote", "Reveal Note in Finder", "Actions", .workspace, one("r", [.command, .shift])),
        define("commandPalette", "Command Palette", "Actions", .workspace, one("k", .command)),
        define("searchNotes", "Search Notes", "Actions", .workspace, one("f", [.command, .shift])),
        define("chooseVault", "Choose Vault", "Actions", .workspace, nil),
        define("settings", "Settings", "Actions", .workspace, one(",", .command)),
        define("calendar.previousWeek", "Previous Week", "Calendar", .calendar, one("leftArrow", .command)),
        define("calendar.nextWeek", "Next Week", "Calendar", .calendar, one("rightArrow", .command)),
        define("assistant.submit", "Send Message", "Assistant", .assistant, one("return", .command)),
        define("assistant.stop", "Stop Answer", "Assistant", .assistant, one(".", .command)),
        define("globalCapture", "Capture Anywhere", "Global", .global, one("space", [.command, .shift])),
        define("panel.home", "Panel: Workspace", "Quick Panel", .quickPanel, one("1", .command)),
        define("panel.agents", "Panel: Agents", "Quick Panel", .quickPanel, one("2", .command)),
        define("panel.sessions", "Panel: Sessions", "Quick Panel", .quickPanel, one("3", .command)),
        define("panel.files", "Panel: Files", "Quick Panel", .quickPanel, one("4", .command)),
        define("panel.projects", "Panel: Projects", "Quick Panel", .quickPanel, one("5", .command)),
        define("panel.workspaces", "Panel: Workspaces", "Quick Panel", .quickPanel, one("6", .command)),
        define("panel.ssh", "Panel: SSH", "Quick Panel", .quickPanel, one("7", .command)),
        define("panel.tmux", "Panel: tmux", "Quick Panel", .quickPanel, one("8", .command)),
        define("panel.shortcuts", "Panel: Shortcuts", "Quick Panel", .quickPanel, one("9", .command)),
        define("panel.music", "Panel: Music", "Quick Panel", .quickPanel, one("0", .command)),
        define("panel.system", "Panel: System", "Quick Panel", .quickPanel, one("s", [.command, .shift])),
        define("panel.attention", "Panel: Attention", "Quick Panel", .quickPanel, one("a", [.command, .shift])),
        define("panel.find", "Panel: Search", "Quick Panel", .quickPanel, one("f", .command)),
        define("panel.refresh", "Panel: Refresh", "Quick Panel", .quickPanel, one("r", .command)),
        define("panel.hide", "Panel: Hide", "Quick Panel", .quickPanel, one("x", .option)),
        define("panel.actions", "Panel: Workspace Actions", "Quick Panel", .quickPanel, one("return", .command)),
        define("panel.zoom", "Panel: Zoom", "Quick Panel", .quickPanel, one("f11")),
        define("panel.help", "Panel: Help", "Quick Panel", .quickPanel, one("f1")),
        define("panel.findFunction", "Panel: Search (Function Key)", "Quick Panel", .quickPanel, one("f3")),
        define("panel.refreshFunction", "Panel: Refresh (Function Key)", "Quick Panel", .quickPanel, one("f9")),
        define("panel.contextMenu", "Panel: Context Menu", "Quick Panel", .quickPanel, one("f10")),
    ]
    private static let definitionsByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
    static func context(for id: String) -> ShortcutContext? { definitionsByID[id]?.context }

    static func binding(for id: String, preferences: Preferences) -> ShortcutBinding? {
        guard let definition = definitionsByID[id] else { return nil }
        if let override = preferences.shortcutOverrides[id] { return override.binding }
        return definition.defaultBinding
    }

    static func label(for id: String, preferences: Preferences) -> String {
        guard let binding = binding(for: id, preferences: preferences) else { return "Not set" }
        return label(for: binding)
    }

    static func label(for binding: ShortcutBinding) -> String {
        binding.strokes.map { stroke in
            if stroke.key == "/" && stroke.modifiers == .shift { return "?" }
            var label = ""
            if stroke.modifiers.contains(.control) { label += "⌃" }
            if stroke.modifiers.contains(.option) { label += "⌥" }
            if stroke.modifiers.contains(.shift) { label += "⇧" }
            if stroke.modifiers.contains(.command) { label += "⌘" }
            return label + keyLabel(stroke.key)
        }.joined(separator: "  then  ")
    }

    private static func keyLabel(_ key: String) -> String {
        switch key {
        case "leftArrow": return "←"
        case "rightArrow": return "→"
        case "upArrow": return "↑"
        case "downArrow": return "↓"
        case "space": return "Space"
        case "return": return "Return"
        case "delete": return "Delete"
        default: return key.uppercased()
        }
    }

    @discardableResult
    static func set(_ binding: ShortcutBinding?, for id: String, preferences: Preferences) -> Result<
        Void, ShortcutBindingError
    > {
        guard let definition = definitionsByID[id] else { return .failure(.unknownAction) }
        if let binding {
            if let error = validate(binding, context: definition.context, id: id) { return .failure(error) }
            for other in definitions where other.id != id && definition.context.overlaps(other.context) {
                if let existing = self.binding(for: other.id, preferences: preferences), conflicts(binding, existing) {
                    return .failure(.conflict(other.title))
                }
            }
        }
        var overrides = preferences.shortcutOverrides
        if binding == definition.defaultBinding {
            overrides.removeValue(forKey: id)
        } else {
            overrides[id] = ShortcutOverride(binding)
        }
        preferences.shortcutOverrides = overrides
        return .success(())
    }

    static func reset(for id: String, preferences: Preferences) -> Result<Void, ShortcutBindingError> {
        guard let definition = definitionsByID[id] else { return .failure(.unknownAction) }
        return set(definition.defaultBinding, for: id, preferences: preferences)
    }

    static func resetAll(preferences: Preferences) { preferences.shortcutOverrides = [:] }

    /// Repair hand-edited values without invalidating unrelated app settings. Defaults take priority.
    static func sanitized(_ overrides: [String: ShortcutOverride]) -> [String: ShortcutOverride] {
        var result: [String: ShortcutOverride] = [:]
        for definition in definitions {
            guard let override = overrides[definition.id] else { continue }
            if let binding = override.binding,
                validate(binding, context: definition.context, id: definition.id) != nil
            {
                continue
            }
            result[definition.id] = override
        }
        // A rejected override restores its default, so recheck until no restored default conflicts.
        while removeFirstConflict(from: &result) {}
        return result
    }

    private static func removeFirstConflict(from result: inout [String: ShortcutOverride]) -> Bool {
        func active(_ definition: KeyboardShortcutDefinition) -> ShortcutBinding? {
            if let override = result[definition.id] { return override.binding }
            return definition.defaultBinding
        }
        for left in definitions.indices {
            let lhs = definitions[left]
            guard let first = active(lhs) else { continue }
            for right in definitions.indices where right > left {
                let rhs = definitions[right]
                guard lhs.context.overlaps(rhs.context), let second = active(rhs),
                    conflicts(first, second)
                else { continue }
                if result[rhs.id]?.binding != nil {
                    result.removeValue(forKey: rhs.id)
                } else if result[lhs.id]?.binding != nil {
                    result.removeValue(forKey: lhs.id)
                } else {
                    continue
                }
                return true
            }
        }
        return false
    }

    static func validate(_ binding: ShortcutBinding, context: ShortcutContext, id: String? = nil)
        -> ShortcutBindingError?
    {
        guard (1...2).contains(binding.strokes.count) else { return .invalidStroke }
        if context == .global && binding.strokes.count != 1 { return .invalidStroke }
        if context == .quickPanel && binding.strokes.count != 1 { return .invalidStroke }
        if id == "assistant.submit", binding.menuShortcut == nil { return .reservedStroke }
        for stroke in binding.strokes {
            if let error = validateStroke(stroke, context: context) { return error }
        }
        return nil
    }

    private static func validateStroke(_ stroke: ShortcutStroke, context: ShortcutContext) -> ShortcutBindingError? {
        let allowed = ShortcutModifiers.command.union(.option).union(.control).union(.shift)
        guard stroke.modifiers.subtracting(allowed).isEmpty, isValidKey(stroke.key) else { return .invalidStroke }
        if stroke.modifiers.isEmpty
            && ["space", "return", "delete", "leftArrow", "rightArrow", "upArrow", "downArrow"].contains(stroke.key)
        {
            return .reservedStroke
        }
        if stroke.modifiers == .command && ["q", "h", "m", "w", "space"].contains(stroke.key) {
            return .reservedStroke
        }
        if context == .quickPanel, isReservedInQuickPanel(stroke) { return .reservedStroke }
        if context == .global && stroke.modifiers.isDisjoint(with: [.command, .option, .control]) {
            return .reservedStroke
        }
        if context == .global && stroke.carbonKeyCode == nil { return .invalidStroke }
        return nil
    }

    private static func isReservedInQuickPanel(_ stroke: ShortcutStroke) -> Bool {
        // The panel dispatches configured shortcuts before its fixed navigation, menus and
        // route-specific function keys. Do not let a binding steal those key events.
        if [
            "f2", "f4", "f5", "f6", "f7", "f8",
            "leftArrow", "rightArrow", "upArrow", "downArrow", "delete",
        ].contains(stroke.key) {
            return true
        }
        if stroke.modifiers.contains(.option),
            ["f", "e", "p", "v", "s", "w", "h"].contains(stroke.key)
        {
            return true
        }
        // Plain and shifted characters are the panel's fixed vim normal-mode keys.
        if stroke.key.utf8.count == 1, stroke.modifiers.isSubset(of: .shift) { return true }
        if stroke.modifiers == .control, ["d", "u", "f", "b", "e", "y"].contains(stroke.key) {
            return true
        }
        if stroke.key == "space" && !stroke.modifiers.contains(.command) { return true }
        if stroke.key == "return" && !stroke.modifiers.contains(.command) { return true }
        return false
    }

    private static func isValidKey(_ key: String) -> Bool {
        let isCharacter =
            key.utf8.count == 1
            && key.utf8.allSatisfy {
                ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57)
                    || ",./;-=\\[]`'".utf8.contains($0)
            }
        let functionNumber = Int(key.dropFirst())
        let isFunction =
            key.hasPrefix("f")
            && functionNumber.map { (1...12).contains($0) && key == "f\($0)" } == true
        return isCharacter
            || ["leftArrow", "rightArrow", "upArrow", "downArrow", "space", "return", "delete"].contains(key)
            || isFunction
    }

    private static func conflicts(_ lhs: ShortcutBinding, _ rhs: ShortcutBinding) -> Bool {
        let common = min(lhs.strokes.count, rhs.strokes.count)
        return lhs.strokes.prefix(common).elementsEqual(rhs.strokes.prefix(common))
    }
}
