import Foundation

/// The vault's Obsidian Daily notes settings (`.obsidian/daily-notes.json`), read only.
///
/// Missing keys take Obsidian's defaults (folder "", format "YYYY-MM-DD", no template). The folder is taken
/// literally; the format is a Moment format whose `/` separators make date-based subfolders.
public struct ObsidianDailyNotes: Equatable {
    public static let configPath = ".obsidian/daily-notes.json"
    public static let defaultFormat = "YYYY-MM-DD"

    public var folder: String
    public var format: String
    /// Vault-relative template path as Obsidian stores it, usually without `.md`. Empty when none is set.
    public var template: String

    public init(folder: String = "", format: String = ObsidianDailyNotes.defaultFormat, template: String = "") {
        self.folder = folder
        self.format = format
        self.template = template
    }

    /// Parses the settings file. Keys of the wrong type count as missing; anything that is not a JSON object
    /// is refused, so a damaged file is never read as "use the defaults".
    public init(json data: Data) throws {
        let object: Any
        if let text = String(bytes: data, encoding: .utf8), text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            object = [String: Any]()
        } else {
            do {
                object = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw VaultError.invalidTemplate("\(Self.configPath) is not valid JSON")
            }
        }
        guard let settings = object as? [String: Any] else {
            throw VaultError.invalidTemplate("\(Self.configPath) is not a JSON object")
        }
        // Obsidian trims the folder and template and treats an empty format as the default.
        let folder = (settings["folder"] as? String) ?? ""
        let format = (settings["format"] as? String) ?? ""
        let template = (settings["template"] as? String) ?? ""
        self.init(
            folder: folder.trimmingCharacters(in: .whitespacesAndNewlines),
            format: format.isEmpty ? Self.defaultFormat : format,
            template: template.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The settings in `vault`, or nil when the vault has no `.obsidian/daily-notes.json`. Reads only.
    public static func load(from vault: NoteVault) throws -> ObsidianDailyNotes? {
        let url = try vault.resolve(relativePath: configPath)
        guard vault.exists(url) else { return nil }
        return try ObsidianDailyNotes(json: Data(vault.load(url).text.utf8))
    }

    /// Vault-relative path of the daily note for `date`.
    public func notePath(for date: Date, formatter: MomentFormat = MomentFormat()) throws -> String {
        try formatter.notePath(folder: folder, format: format, for: date)
    }

    /// Vault-relative path of the template file, or nil when no template is set.
    public var templatePath: String? {
        var path = template
        while path.hasPrefix("/") { path.removeFirst() }
        guard !path.isEmpty else { return nil }
        return path.lowercased().hasSuffix(".md") ? path : path + ".md"
    }

    /// The template text at `path`, or nil when that file does not exist. Reads through `NoteVault`, so the
    /// path cannot leave the vault and a non-UTF-8 file is refused; nothing is ever written.
    public static func readTemplate(at path: String, in vault: NoteVault) throws -> String? {
        let url = try vault.resolve(relativePath: path)
        guard vault.exists(url) else { return nil }
        return try vault.load(url).text
    }

    /// `body` with Obsidian's core template variables filled in for `date`: `{{date}}`, `{{time}}`, `{{title}}`,
    /// `{{date:FORMAT}}` and `{{time:FORMAT}}` (names are case-insensitive, spaces inside the braces allowed).
    /// Anything else, including a format with an unsupported token, is left exactly as written.
    public static func render(
        template body: String, title: String, date: Date, formatter: MomentFormat = MomentFormat(),
        dateFormat: String = "YYYY-MM-DD", timeFormat: String = "HH:mm"
    ) -> String {
        /// The value of one `{{…}}`, or nil to keep it as written.
        func value(of inner: Substring) -> String? {
            let colon = inner.firstIndex(of: ":")
            let name = inner[..<(colon ?? inner.endIndex)].trimmingCharacters(in: .whitespaces).lowercased()
            let format = colon.map { inner[inner.index(after: $0)...].trimmingCharacters(in: .whitespaces) }
            switch (name, format) {
            case ("title", nil): return title
            case ("date", nil): return try? formatter.string(dateFormat, for: date)
            case ("time", nil): return try? formatter.string(timeFormat, for: date)
            case ("date", let format?), ("time", let format?):
                return format.isEmpty ? nil : try? formatter.string(format, for: date)
            default: return nil
            }
        }

        var output = ""
        var rest = Substring(body)
        while let open = rest.range(of: "{{") {
            output += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}") else {
                rest = rest[open.lowerBound...]
                break
            }
            if let replacement = value(of: rest[open.upperBound..<close.lowerBound]) {
                output += replacement
            } else {
                output += rest[open.lowerBound..<close.upperBound]
            }
            rest = rest[close.upperBound...]
        }
        return output + rest
    }
}
