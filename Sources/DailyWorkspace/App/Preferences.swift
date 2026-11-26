import DailyCore
import Foundation

protocol SettingsPersisting {
    /// nil when nothing has been saved yet.
    func load() throws -> WorkspaceSettings?
    func save(_ settings: WorkspaceSettings) throws
}

extension SettingsPersistence: SettingsPersisting {}

/// Every remembered setting. Each change is written to `settings.json` in the workspace folder.
@MainActor
final class Preferences: ObservableObject {
    /// UserDefaults keys used before settings moved to `settings.json`. Read once, on the first launch
    /// without a settings file, and never written.
    enum LegacyKey {
        static let vaultBookmark = "vaultBookmark"
        static let dailyFolder = "dailyFolder"
        static let dailyFilename = "dailyFilename"
        static let caretPreset = "caretPreset"
        static let recentNotes = "recentNotes"
        static let showNotePreview = "notePreview"

        static let all = [vaultBookmark, dailyFolder, dailyFilename, caretPreset, recentNotes, showNotePreview]
    }

    static let recentNotesLimit = 8

    /// Where the daily-note location comes from: the vault's Obsidian settings (default) or the fields below.
    @Published var dailyNoteSource: DailyNoteSource { didSet { persist() } }
    @Published var dailyFolder: String { didSet { persist() } }
    @Published var dailyFilename: String { didSet { persist() } }
    @Published var caretPreset: CaretPreset { didSet { persist() } }
    @Published var showNotePreview: Bool { didSet { persist() } }
    /// Off by default: while off, the Assistant sends nothing to an AI provider.
    @Published var assistantEnabled: Bool { didSet { persist() } }
    @Published var assistantProvider: AssistantProvider { didSet { persist() } }
    /// Separate model choices prevent reusing a provider-specific model ID after switching.
    @Published var assistantModel: String { didSet { persist() } }
    @Published var openRouterModel: String { didSet { persist() } }
    /// The Assistant's loop limits and tool choices. Stored validated, so every value is in range.
    @Published var assistantRuntime: AssistantRuntimeSettings {
        didSet {
            // Assigning inside its own observer does not re-run the observer.
            let valid = assistantRuntime.validated
            if valid != assistantRuntime { assistantRuntime = valid }
            persist()
        }
    }
    /// Saved chats, memory, routines and vault-write approval. Stored validated.
    @Published var agent: AgentSettings {
        didSet {
            let valid = agent.validated
            if valid != agent { agent = valid }
            persist()
        }
    }
    @Published var mailEnabled: Bool { didSet { persist() } }
    @Published var quickPanelClipboardEnabled: Bool { didSet { persist() } }
    @Published var quickPanelTerminalBorderEnabled: Bool { didSet { persist() } }
    @Published var quickPanelZoom: [String: Double] { didSet { persist() } }
    @Published var shortcutOverrides: [String: ShortcutOverride] { didSet { persist() } }
    /// Transient: suspends the registered global hotkey while Settings records a replacement.
    @Published var isRecordingShortcut = false
    @Published private(set) var recentNotes: [String]
    /// Security-scoped bookmark of the chosen vault folder.
    private(set) var vaultBookmark: Data?
    private(set) var vaultPath: String?

    private let store: SettingsPersisting
    /// False when the settings file exists but could not be read: saving would overwrite it.
    private let canSave: Bool

    init(store: SettingsPersisting, legacyDefaults: UserDefaults? = nil) {
        self.store = store
        var settings = WorkspaceSettings()
        var imported = false
        var readable = true
        do {
            if let saved = try store.load() {
                settings = saved
            } else if let legacyDefaults, let legacy = Self.importLegacy(from: legacyDefaults) {
                settings = legacy
                imported = true
            }
        } catch {
            readable = false
            Log.app.error(
                "Settings could not be read, so changes will not be saved: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
        }
        canSave = readable
        dailyNoteSource = settings.dailyNoteSource
        dailyFolder = settings.dailyFolder
        dailyFilename = settings.dailyFilename
        caretPreset = settings.caretPreset
        showNotePreview = settings.showNotePreview
        assistantEnabled = settings.assistantEnabled
        assistantProvider = settings.assistantProvider
        assistantModel = settings.assistantModel
        openRouterModel = settings.openRouterModel
        assistantRuntime = settings.assistantRuntime.validated
        agent = settings.agent.validated
        mailEnabled = settings.mailEnabled
        quickPanelClipboardEnabled = settings.quickPanelClipboardEnabled
        quickPanelTerminalBorderEnabled = settings.quickPanelTerminalBorderEnabled
        quickPanelZoom = settings.quickPanelZoom
        shortcutOverrides = KeyboardShortcutCatalog.sanitized(settings.shortcutOverrides)
        recentNotes = settings.recentNotes
        vaultBookmark = settings.vaultBookmark
        vaultPath = settings.vaultPath
        if imported {
            Log.app.info("Imported settings from UserDefaults")
            persist()
        }
    }

    var selectedAssistantModel: String {
        assistantProvider == .anthropic ? assistantModel : openRouterModel
    }

    var dailyNoteTemplate: DailyNoteTemplate { DailyNoteTemplate(folder: dailyFolder, filename: dailyFilename) }

    var dailyNoteResolver: DailyNoteResolver {
        DailyNoteResolver(source: dailyNoteSource, custom: dailyNoteTemplate)
    }

    func rememberVault(at url: URL, bookmark: Data) {
        vaultBookmark = bookmark
        vaultPath = url.path
        persist()
    }

    /// Keep the human-readable path current when the bookmark resolves somewhere new (e.g. a moved vault).
    func noteVaultLocation(_ url: URL) {
        guard vaultPath != url.path else { return }
        vaultPath = url.path
        persist()
    }

    func rememberRecent(_ path: String) {
        var list = recentNotes.filter { $0 != path }
        list.insert(path, at: 0)
        recentNotes = Array(list.prefix(Self.recentNotesLimit))
        persist()
    }

    private var snapshot: WorkspaceSettings {
        WorkspaceSettings(
            vaultBookmark: vaultBookmark,
            vaultPath: vaultPath,
            dailyNoteSource: dailyNoteSource,
            dailyFolder: dailyFolder,
            dailyFilename: dailyFilename,
            caretPreset: caretPreset,
            showNotePreview: showNotePreview,
            recentNotes: recentNotes,
            assistantEnabled: assistantEnabled,
            assistantProvider: assistantProvider,
            assistantModel: assistantModel,
            openRouterModel: openRouterModel,
            mailEnabled: mailEnabled,
            quickPanelClipboardEnabled: quickPanelClipboardEnabled,
            quickPanelTerminalBorderEnabled: quickPanelTerminalBorderEnabled,
            quickPanelZoom: quickPanelZoom,
            shortcutOverrides: shortcutOverrides,
            assistantRuntime: assistantRuntime,
            agent: agent
        )
    }

    private func persist() {
        guard canSave else { return }
        do {
            try store.save(snapshot)
        } catch {
            Log.app.error(
                "Settings could not be saved: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
        }
    }

    /// Settings from the UserDefaults keys of earlier versions, or nil when none were ever set.
    static func importLegacy(from defaults: UserDefaults) -> WorkspaceSettings? {
        guard LegacyKey.all.contains(where: { defaults.object(forKey: $0) != nil }) else { return nil }
        var settings = WorkspaceSettings()
        settings.vaultBookmark = defaults.data(forKey: LegacyKey.vaultBookmark)
        if let value = defaults.string(forKey: LegacyKey.dailyFolder) { settings.dailyFolder = value }
        if let value = defaults.string(forKey: LegacyKey.dailyFilename) { settings.dailyFilename = value }
        if let value = defaults.string(forKey: LegacyKey.caretPreset), let preset = CaretPreset(rawValue: value) {
            settings.caretPreset = preset
        }
        settings.showNotePreview = defaults.bool(forKey: LegacyKey.showNotePreview)
        settings.recentNotes = defaults.stringArray(forKey: LegacyKey.recentNotes) ?? []
        return settings
    }
}
