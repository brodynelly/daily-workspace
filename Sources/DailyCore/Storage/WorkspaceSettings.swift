import Foundation

/// The network provider selected for Assistant turns. Credentials remain separate Keychain entries.
public enum AssistantProvider: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openRouter

    public var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openRouter: "OpenRouter"
        }
    }
}

/// Everything the app remembers between launches, saved as `settings.json`.
/// Missing keys fall back to defaults and unknown keys are ignored, so the file can be edited by hand.
public struct WorkspaceSettings: Codable, Equatable {
    /// Security-scoped bookmark of the chosen vault folder.
    public var vaultBookmark: Data?
    /// The vault's path when last opened. For people reading the file; the app opens the bookmark.
    public var vaultPath: String?
    /// Where the daily-note location comes from. Defaults to the vault's Obsidian settings.
    public var dailyNoteSource: DailyNoteSource
    public var dailyFolder: String
    public var dailyFilename: String
    public var caretPreset: CaretPreset
    public var showNotePreview: Bool
    public var recentNotes: [String]
    /// Off until the user turns the Assistant on. While off, nothing is sent to an AI provider.
    public var assistantEnabled: Bool
    public var assistantProvider: AssistantProvider
    /// The Anthropic model ID the Assistant asks. Blank means the default.
    public var assistantModel: String
    /// The OpenRouter model ID. Kept separately so changing providers does not send an ID to the wrong API.
    public var openRouterModel: String
    /// External Mail access requires explicit opt-in.
    public var mailEnabled: Bool
    /// Quick Panel clipboard access requires explicit opt-in.
    public var quickPanelClipboardEnabled: Bool
    /// Quick Panel terminal border integration requires explicit opt-in.
    public var quickPanelTerminalBorderEnabled: Bool
    /// User bindings keyed by stable command ID. Missing IDs use the catalog's defaults.
    public var shortcutOverrides: [String: ShortcutOverride]

    public static let defaultAssistantModel = "claude-opus-5-5"
    public static let defaultOpenRouterModel = "anthropic/claude-sonnet-4"

    public init(
        vaultBookmark: Data? = nil,
        vaultPath: String? = nil,
        dailyNoteSource: DailyNoteSource = .obsidian,
        dailyFolder: String = "",
        dailyFilename: String = "YYYY-MM-DD",
        caretPreset: CaretPreset = .glide,
        showNotePreview: Bool = false,
        recentNotes: [String] = [],
        assistantEnabled: Bool = false,
        assistantProvider: AssistantProvider = .anthropic,
        assistantModel: String = WorkspaceSettings.defaultAssistantModel,
        openRouterModel: String = WorkspaceSettings.defaultOpenRouterModel,
        mailEnabled: Bool = false,
        quickPanelClipboardEnabled: Bool = false,
        quickPanelTerminalBorderEnabled: Bool = false,
        shortcutOverrides: [String: ShortcutOverride] = [:]
    ) {
        self.vaultBookmark = vaultBookmark
        self.vaultPath = vaultPath
        self.dailyNoteSource = dailyNoteSource
        self.dailyFolder = dailyFolder
        self.dailyFilename = dailyFilename
        self.caretPreset = caretPreset
        self.showNotePreview = showNotePreview
        self.recentNotes = recentNotes
        self.assistantEnabled = assistantEnabled
        self.assistantProvider = assistantProvider
        self.assistantModel = assistantModel
        self.openRouterModel = openRouterModel
        self.mailEnabled = mailEnabled
        self.quickPanelClipboardEnabled = quickPanelClipboardEnabled
        self.quickPanelTerminalBorderEnabled = quickPanelTerminalBorderEnabled
        self.shortcutOverrides = shortcutOverrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = WorkspaceSettings()
        vaultBookmark = try c.decodeIfPresent(Data.self, forKey: .vaultBookmark)
        vaultPath = try c.decodeIfPresent(String.self, forKey: .vaultPath)
        // An unknown source (a typo, or one from a newer version) falls back to the Obsidian settings.
        dailyNoteSource =
            (try? c.decodeIfPresent(DailyNoteSource.self, forKey: .dailyNoteSource)) ?? fallback.dailyNoteSource
        dailyFolder = try c.decodeIfPresent(String.self, forKey: .dailyFolder) ?? fallback.dailyFolder
        dailyFilename = try c.decodeIfPresent(String.self, forKey: .dailyFilename) ?? fallback.dailyFilename
        // An unknown preset name (a typo, or one from a newer version) keeps the rest of the file usable.
        caretPreset = (try? c.decodeIfPresent(CaretPreset.self, forKey: .caretPreset)) ?? fallback.caretPreset
        showNotePreview = try c.decodeIfPresent(Bool.self, forKey: .showNotePreview) ?? fallback.showNotePreview
        recentNotes = try c.decodeIfPresent([String].self, forKey: .recentNotes) ?? fallback.recentNotes
        // A value of the wrong type keeps the Assistant off rather than making the whole file unreadable.
        assistantEnabled =
            (try? c.decodeIfPresent(Bool.self, forKey: .assistantEnabled)) ?? fallback.assistantEnabled
        assistantProvider =
            (try? c.decodeIfPresent(AssistantProvider.self, forKey: .assistantProvider)) ?? fallback.assistantProvider
        assistantModel = (try? c.decodeIfPresent(String.self, forKey: .assistantModel)) ?? fallback.assistantModel
        openRouterModel = (try? c.decodeIfPresent(String.self, forKey: .openRouterModel)) ?? fallback.openRouterModel
        // Malformed consent values cannot opt into external sources or integrations.
        mailEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .mailEnabled)) ?? fallback.mailEnabled
        quickPanelClipboardEnabled =
            (try? c.decodeIfPresent(Bool.self, forKey: .quickPanelClipboardEnabled))
            ?? fallback.quickPanelClipboardEnabled
        quickPanelTerminalBorderEnabled =
            (try? c.decodeIfPresent(Bool.self, forKey: .quickPanelTerminalBorderEnabled))
            ?? fallback.quickPanelTerminalBorderEnabled
        // A malformed individual binding must not discard unrelated settings or healthy shortcuts.
        if let overrides = try? c.nestedContainer(keyedBy: ShortcutIDKey.self, forKey: .shortcutOverrides) {
            var decoded: [String: ShortcutOverride] = [:]
            for key in overrides.allKeys {
                if let value = try? overrides.decode(ShortcutOverride.self, forKey: key) {
                    decoded[key.stringValue] = value
                }
            }
            shortcutOverrides = decoded
        } else {
            shortcutOverrides = [:]
        }
    }
}

private struct ShortcutIDKey: CodingKey {
    let stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
}

/// JSON persistence for `WorkspaceSettings`. A corrupt file is moved aside, never overwritten silently.
public struct SettingsPersistence {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The saved settings, or nil when none exist yet. A file that is not valid settings JSON is renamed
    /// to `settings.corrupt-<time>.json` and nil is returned; if it cannot be renamed, this throws.
    public func load() throws -> WorkspaceSettings? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(WorkspaceSettings.self, from: data)
        } catch {
            let aside = url.deletingLastPathComponent().appendingPathComponent(
                "settings.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    public func save(_ settings: WorkspaceSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}
