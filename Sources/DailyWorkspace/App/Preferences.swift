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
        static let openRouterModel = "openRouterModel"

        static let all = [
            vaultBookmark, dailyFolder, dailyFilename, caretPreset, recentNotes, showNotePreview, openRouterModel,
        ]
    }

    static let recentNotesLimit = 8

    /// Where the daily-note location comes from: the vault's Obsidian settings (default) or the fields below.
    @Published var dailyNoteSource: DailyNoteSource { didSet { persist() } }
    @Published var dailyFolder: String { didSet { persist() } }
    @Published var dailyFilename: String { didSet { persist() } }
    @Published var caretPreset: CaretPreset { didSet { persist() } }
    @Published var showNotePreview: Bool { didSet { persist() } }
    /// Blank means the OpenRouter account default.
    @Published var openRouterModel: String { didSet { persist() } }
    /// Off by default: while off, the Assistant sends nothing to Anthropic.
    @Published var assistantEnabled: Bool { didSet { persist() } }
    /// The Anthropic model ID; blank means `WorkspaceSettings.defaultAssistantModel`.
    @Published var assistantModel: String { didSet { persist() } }
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
        openRouterModel = settings.openRouterModel
        assistantEnabled = settings.assistantEnabled
        assistantModel = settings.assistantModel
        recentNotes = settings.recentNotes
        vaultBookmark = settings.vaultBookmark
        vaultPath = settings.vaultPath
        if imported {
            Log.app.info("Imported settings from UserDefaults")
            persist()
        }
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
            openRouterModel: openRouterModel,
            recentNotes: recentNotes,
            assistantEnabled: assistantEnabled,
            assistantModel: assistantModel
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
        if let value = defaults.string(forKey: LegacyKey.openRouterModel) { settings.openRouterModel = value }
        settings.recentNotes = defaults.stringArray(forKey: LegacyKey.recentNotes) ?? []
        return settings
    }
}
