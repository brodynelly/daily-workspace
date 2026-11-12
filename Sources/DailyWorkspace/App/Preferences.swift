import DailyCore
import Foundation

/// Every UserDefaults-backed value. Keys are declared here and nowhere else.
@MainActor
final class Preferences: ObservableObject {
    enum Key {
        static let vaultBookmark = "vaultBookmark"
        static let dailyFolder = "dailyFolder"
        static let dailyFilename = "dailyFilename"
        static let caretPreset = "caretPreset"
        static let recentNotes = "recentNotes"
        static let showNotePreview = "notePreview"
        static let openRouterModel = "openRouterModel"
    }

    static let recentNotesLimit = 8

    @Published var dailyFolder: String { didSet { defaults.set(dailyFolder, forKey: Key.dailyFolder) } }
    @Published var dailyFilename: String { didSet { defaults.set(dailyFilename, forKey: Key.dailyFilename) } }
    @Published var caretPreset: CaretPreset { didSet { defaults.set(caretPreset.rawValue, forKey: Key.caretPreset) } }
    @Published var showNotePreview: Bool { didSet { defaults.set(showNotePreview, forKey: Key.showNotePreview) } }
    /// Blank means the OpenRouter account default.
    @Published var openRouterModel: String { didSet { defaults.set(openRouterModel, forKey: Key.openRouterModel) } }
    @Published private(set) var recentNotes: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dailyFolder = defaults.string(forKey: Key.dailyFolder) ?? ""
        dailyFilename = defaults.string(forKey: Key.dailyFilename) ?? "YYYY-MM-DD"
        caretPreset = CaretPreset(rawValue: defaults.string(forKey: Key.caretPreset) ?? "") ?? .glide
        showNotePreview = defaults.bool(forKey: Key.showNotePreview)
        openRouterModel = defaults.string(forKey: Key.openRouterModel) ?? ""
        recentNotes = defaults.stringArray(forKey: Key.recentNotes) ?? []
    }

    var dailyNoteTemplate: DailyNoteTemplate { DailyNoteTemplate(folder: dailyFolder, filename: dailyFilename) }

    /// Security-scoped bookmark of the chosen vault folder.
    var vaultBookmark: Data? {
        get { defaults.data(forKey: Key.vaultBookmark) }
        set { defaults.set(newValue, forKey: Key.vaultBookmark) }
    }

    func rememberRecent(_ path: String) {
        var list = recentNotes.filter { $0 != path }
        list.insert(path, at: 0)
        recentNotes = Array(list.prefix(Self.recentNotesLimit))
        defaults.set(recentNotes, forKey: Key.recentNotes)
    }
}
