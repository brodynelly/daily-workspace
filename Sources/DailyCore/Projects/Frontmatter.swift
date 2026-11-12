import Foundation

/// A deliberately small YAML subset: `key: scalar`, `key: [a, b]` and `key:` followed by `- item` lines.
/// Anything else (nested maps, multi-line strings) is ignored rather than guessed.
public struct Frontmatter: Hashable, Sendable {
    public var scalars: [String: String] = [:]
    public var lists: [String: [String]] = [:]

    public init() {}

    /// Parses a bare YAML document.
    public init(yaml: String) {
        self.init(lines: SourceFile.lines(yaml))
    }

    /// The frontmatter block at the very start of a Markdown note, and the line index after it.
    /// Nil when the note has no `---` block.
    public static func split(markdown: String) -> (frontmatter: Frontmatter, bodyStart: Int)? {
        let lines = SourceFile.lines(markdown)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard
            let end = lines.dropFirst().firstIndex(where: {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return trimmed == "---" || trimmed == "..."
            })
        else { return nil }
        return (Frontmatter(lines: Array(lines[1..<end])), end + 1)
    }

    /// `tags` as a list, whichever way it was written.
    public var tags: [String] { values("tags") }

    /// A key's list, or its scalar as a one-element list.
    public func values(_ key: String) -> [String] {
        if let list = lists[key] { return list }
        return scalars[key].map { [$0] } ?? []
    }

    init(lines: [Substring]) {
        var currentList: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let key = currentList, trimmed.hasPrefix("- ") || trimmed == "-" {
                let item = Self.unquote(String(trimmed.dropFirst()))
                if !item.isEmpty { lists[key, default: []].append(item) }
                continue
            }
            currentList = nil
            guard line.first?.isWhitespace != true, let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            assign(key: key, value: value, currentList: &currentList)
        }
    }

    private mutating func assign(key: String, value: String, currentList: inout String?) {
        guard !key.isEmpty, scalars[key] == nil, lists[key] == nil else { return }
        if value.isEmpty {
            currentList = key
        } else if value.hasPrefix("["), value.hasSuffix("]") {
            lists[key] = value.dropFirst().dropLast().split(separator: ",").map { Self.unquote(String($0)) }
                .filter { !$0.isEmpty }
        } else {
            scalars[key] = Self.unquote(value)
        }
    }

    static func unquote(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, first == trimmed.last, first == "\"" || first == "'"
        else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }
}
