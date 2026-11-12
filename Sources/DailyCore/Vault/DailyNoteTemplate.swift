import Foundation

/// Maps a date to the vault-relative path of its daily note. Tokens: YYYY, MM, DD.
public struct DailyNoteTemplate: Equatable {
    public var folder: String
    public var filename: String

    public init(folder: String = "", filename: String = "YYYY-MM-DD") {
        self.folder = folder
        self.filename = filename
    }

    public func relativePath(for date: Date, calendar: Calendar = .current) throws -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { throw VaultError.invalidTemplate("date") }

        func render(_ s: String) -> String {
            s.replacingOccurrences(of: "YYYY", with: String(format: "%04d", y))
                .replacingOccurrences(of: "MM", with: String(format: "%02d", m))
                .replacingOccurrences(of: "DD", with: String(format: "%02d", d))
        }

        var name = render(filename).trimmingCharacters(in: .whitespaces)
        let parts = folder.split(separator: "/").map { render(String($0)).trimmingCharacters(in: .whitespaces) }.filter
        { !$0.isEmpty }

        guard !name.isEmpty else { throw VaultError.invalidTemplate("empty file name") }
        for part in parts + [name] {
            if part == "." || part == ".." || part.contains("/") || part.contains("\\") || part.contains("\0") {
                throw VaultError.invalidTemplate("path segments not allowed")
            }
        }
        if !name.lowercased().hasSuffix(".md") { name += ".md" }
        return (parts + [name]).joined(separator: "/")
    }
}
