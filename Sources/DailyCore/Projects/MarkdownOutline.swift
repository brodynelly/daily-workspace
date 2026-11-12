import Foundation

/// Headings, sections, prose and bullets of a Markdown body. Fenced code is never treated as structure.
struct MarkdownOutline {
    struct Section {
        let level: Int
        let title: String
        /// The section's lines after its heading, up to the next heading of the same or a higher level.
        let lines: [Substring]
    }

    private struct Heading {
        let index: Int
        let level: Int
        let title: String
    }

    /// The first H1.
    let title: String?
    /// Lines after the H1 and before the first lower-level heading.
    let preamble: [Substring]
    let sections: [Section]

    init<Lines: Collection>(_ body: Lines) where Lines.Element == Substring {
        let lines = Array(body)
        let code = Self.codeMask(lines)
        let headings: [Heading] = lines.indices.compactMap { index in
            guard !code[index], let heading = Self.heading(lines[index]) else { return nil }
            return Heading(index: index, level: heading.level, title: heading.title)
        }
        let h1 = headings.first { $0.level == 1 }
        title = h1?.title
        let firstSection = headings.first { $0.level > 1 && $0.index > (h1?.index ?? -1) }
        let preambleStart = (h1?.index ?? -1) + 1
        preamble = Array(lines[preambleStart..<max(preambleStart, firstSection?.index ?? lines.count)])
        sections = headings.enumerated().compactMap { position, heading in
            guard heading.level > 1 else { return nil }
            let end = headings[(position + 1)...].first { $0.level <= heading.level }?.index ?? lines.count
            let content = lines[(heading.index + 1)..<end].indices.filter { !code[$0] }.map { lines[$0] }
            return Section(level: heading.level, title: heading.title, lines: content)
        }
    }

    /// The first section whose title contains one of `aliases` (case-insensitive).
    func section(matching aliases: [String]) -> Section? {
        sections.first { section in
            let title = section.title.lowercased()
            return aliases.contains { title.contains($0) }
        }
    }

    static func heading(_ line: Substring) -> (level: Int, title: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        let text = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        let title = text.trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
        return (hashes.count, title)
    }

    /// True for lines inside (or delimiting) fenced code.
    static func codeMask(_ lines: [Substring]) -> [Bool] {
        var inside = false
        return lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inside.toggle()
                return true
            }
            return inside
        }
    }

    /// Paragraphs of plain prose, each unwrapped onto one line. Lists, tables, quotes, callouts,
    /// headings and comments are not prose.
    static func paragraphs(_ lines: [Substring]) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isProse(trimmed) {
                current.append(trimmed)
            } else if !current.isEmpty {
                paragraphs.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        return paragraphs
    }

    private static func isProse(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty, !isBullet(trimmed) else { return false }
        let markers = ["|", ">", "#", "<!--", "%%", "---", "[["]
        return !markers.contains { trimmed.hasPrefix($0) }
    }

    private static func isBullet(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") || trimmed == "-" {
            return true
        }
        let digits = trimmed.prefix { $0.isNumber }
        return !digits.isEmpty && trimmed.dropFirst(digits.count).hasPrefix(". ")
    }

    /// Top-level list items, with their wrapped continuation lines joined. Empty items are dropped.
    static func bullets(_ lines: [Substring]) -> [String] {
        var items: [String] = []
        var current: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indented = line.first?.isWhitespace == true
            if !indented, isBullet(trimmed) {
                if let current, !current.isEmpty { items.append(current) }
                current = String(trimmed.drop { $0 != " " }).trimmingCharacters(in: .whitespaces)
            } else if trimmed.isEmpty || (!indented && current != nil) {
                if let current, !current.isEmpty { items.append(current) }
                current = nil
            } else if let existing = current {
                current = existing + " " + trimmed
            }
        }
        if let current, !current.isEmpty { items.append(current) }
        return items
    }

    /// `text` cut to at most `limit` characters at a word boundary, with an ellipsis when cut.
    static func bounded(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = text.prefix(limit)
        let cut = prefix.lastIndex(of: " ").map { prefix[..<$0] } ?? prefix
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }
}
