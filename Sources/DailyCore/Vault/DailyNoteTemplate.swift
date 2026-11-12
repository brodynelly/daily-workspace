import Foundation

/// The app's own daily-note setting (Settings → Vault → Custom): a folder, taken literally, and a file name
/// in Moment format (`MomentFormat`), which may contain `/` for date-based subfolders.
public struct DailyNoteTemplate: Equatable {
    public var folder: String
    public var filename: String

    public init(folder: String = "", filename: String = "YYYY-MM-DD") {
        self.folder = folder
        self.filename = filename
    }

    public func relativePath(for date: Date, formatter: MomentFormat = MomentFormat()) throws -> String {
        var format = filename.trimmingCharacters(in: .whitespaces)
        // `.md` is added anyway; a typed one would otherwise render as minute and weekday tokens.
        if format.lowercased().hasSuffix(".md") { format.removeLast(3) }
        guard !format.isEmpty else { throw VaultError.invalidTemplate("empty file name") }
        return try formatter.notePath(folder: folder, format: format, for: date)
    }
}

/// Where the daily-note location comes from.
public enum DailyNoteSource: String, Codable, CaseIterable {
    /// The vault's `.obsidian/daily-notes.json`, falling back to the custom setting when the vault has none.
    case obsidian
    /// The app's own folder and file name.
    case custom
}

/// Today's daily note as resolved from the settings.
public struct DailyNoteResolution: Equatable {
    public enum Origin: Equatable {
        /// From `.obsidian/daily-notes.json`.
        case obsidian(ObsidianDailyNotes)
        /// The vault has no Obsidian settings, so the custom setting was used.
        case customFallback
        case custom
    }

    public var path: String
    /// Vault-relative template to fill a new note from, when one is configured.
    public var templatePath: String?
    public var origin: Origin

    /// The note's file name without `.md`: Obsidian's `{{title}}`.
    public var title: String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
    }
}

/// Decides where today's daily note lives. Never resolves a note in the vault root unless the user chose the
/// custom setting with an empty folder: with the Obsidian source, a root path is refused instead.
public struct DailyNoteResolver {
    public var source: DailyNoteSource
    public var custom: DailyNoteTemplate
    public var formatter: MomentFormat

    public init(source: DailyNoteSource, custom: DailyNoteTemplate, formatter: MomentFormat = MomentFormat()) {
        self.source = source
        self.custom = custom
        self.formatter = formatter
    }

    /// Reads `.obsidian/daily-notes.json` (never writes). Throws `VaultError.dailyNoteFolderUnset` when the
    /// note would land in the vault root without the user having chosen that, and `invalidTemplate` for a
    /// setting that cannot be rendered safely.
    public func resolve(in vault: NoteVault, for date: Date) throws -> DailyNoteResolution {
        let resolution: DailyNoteResolution
        switch source {
        case .custom:
            return DailyNoteResolution(
                path: try custom.relativePath(for: date, formatter: formatter), templatePath: nil, origin: .custom)
        case .obsidian:
            if let settings = try ObsidianDailyNotes.load(from: vault) {
                resolution = DailyNoteResolution(
                    path: try settings.notePath(for: date, formatter: formatter),
                    templatePath: settings.templatePath, origin: .obsidian(settings))
            } else {
                resolution = DailyNoteResolution(
                    path: try custom.relativePath(for: date, formatter: formatter), templatePath: nil,
                    origin: .customFallback)
            }
        }
        guard resolution.path.contains("/") else { throw VaultError.dailyNoteFolderUnset }
        return resolution
    }
}
