import Foundation

/// The Org to-do vocabulary of one file: active states, then done states.
public struct OrgTodoKeywords: Hashable, Sendable {
    public let active: [String]
    public let done: [String]

    public init(active: [String], done: [String]) {
        self.active = active
        self.done = done
    }

    /// Used when a file declares no in-buffer to-do sequence (`#+SEQ_TODO:`, `#+TYP_TODO:` or the plain form).
    public static let standard = OrgTodoKeywords(
        active: ["TODO", "NEXT", "WAIT", "WAITING", "HOLD"], done: ["DONE", "CANCELLED", "CANCELED"])

    public var all: [String] { active + done }

    public func isDone(_ keyword: String) -> Bool { done.contains(keyword) }

    /// Keywords declared in the file's in-buffer settings, or nil when there are none. Several lines
    /// add up. Fast-access keys such as `NEXT(n)` or `DONE(d!)` are stripped. A sequence without `|`
    /// treats its last word as the done state, as Org does.
    public static func declared(in lines: [Substring]) -> OrgTodoKeywords? {
        var active: [String] = []
        var done: [String] = []
        var found = false
        for line in lines {
            guard let words = settingWords(line) else { continue }
            found = true
            let sequence = split(words)
            active += sequence.active
            done += sequence.done
        }
        return found ? OrgTodoKeywords(active: active, done: done) : nil
    }

    private static func settingWords(_ line: Substring) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let upper = trimmed.uppercased()
        for prefix in ["#+TODO:", "#+SEQ_TODO:", "#+TYP_TODO:"] where upper.hasPrefix(prefix) {
            return trimmed.dropFirst(prefix.count).split(whereSeparator: \.isWhitespace).map {
                String($0.prefix { $0 != "(" })
            }.filter { !$0.isEmpty }
        }
        return nil
    }

    private static func split(_ words: [String]) -> (active: [String], done: [String]) {
        if let bar = words.firstIndex(of: "|") {
            return (Array(words[..<bar]), Array(words[(bar + 1)...]).filter { $0 != "|" })
        }
        guard let last = words.last else { return ([], []) }
        return (Array(words.dropLast()), [last])
    }
}

/// Org timestamp parsing. Active `<…>` and inactive `[…]`, with an optional day name, time, time range,
/// repeater and warning period; only the date and the first time are kept.
enum OrgTimestamp {
    private static let pattern = try? NSRegularExpression(
        pattern: #"<(\d{4})-(\d{2})-(\d{2})([^>\n]*)>|\[(\d{4})-(\d{2})-(\d{2})([^\]\n]*)\]"#)
    private static let timePattern = try? NSRegularExpression(pattern: #"(?:^|\s)(\d{1,2}):(\d{2})"#)
    private static let planningPattern = try? NSRegularExpression(
        pattern: #"\b(SCHEDULED|DEADLINE|CLOSED):\s*(<[^>\n]*>|\[[^\]\n]*\])"#)

    /// The first timestamp in `text`.
    static func parse(_ text: String) -> LoopDate? {
        let ns = text as NSString
        guard let match = pattern?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let isActive = match.range(at: 1).location != NSNotFound
        let base = isActive ? 1 : 5
        func group(_ offset: Int) -> String { ns.substring(with: match.range(at: base + offset)) }
        guard let year = Int(group(0)), let month = Int(group(1)), let day = Int(group(2)),
            (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        let time = clock(in: group(3))
        return LoopDate(
            year: year, month: month, day: day, hour: time?.hour, minute: time?.minute, isActive: isActive,
            raw: ns.substring(with: match.range))
    }

    private static func clock(in text: String) -> (hour: Int, minute: Int)? {
        let ns = text as NSString
        guard let match = timePattern?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
            let hour = Int(ns.substring(with: match.range(at: 1))),
            let minute = Int(ns.substring(with: match.range(at: 2))), hour < 24, minute < 60
        else { return nil }
        return (hour, minute)
    }

    /// `SCHEDULED:`/`DEADLINE:`/`CLOSED:` entries on a planning line, keyed by keyword. Nil when the line
    /// is not a planning line.
    static func planning(_ line: Substring) -> [String: LoopDate]? {
        let text = String(line)
        let ns = text as NSString
        let matches = planningPattern?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        guard !matches.isEmpty else { return nil }
        var result: [String: LoopDate] = [:]
        for match in matches {
            guard let date = parse(ns.substring(with: match.range(at: 2))) else { continue }
            result[ns.substring(with: match.range(at: 1))] = date
        }
        return result
    }
}

/// The parts of one headline: `** NEXT [#A] Title :tag1:tag2:`.
struct OrgHeadline {
    let level: Int
    let keyword: String?
    let priority: String?
    let title: String
    let tags: [String]

    private static let tagsPattern = try? NSRegularExpression(pattern: #"(?:^|\s+)(:(?:[\w@#%]+:)+)\s*$"#)
    private static let priorityPattern = try? NSRegularExpression(pattern: #"^\[#([A-Za-z0-9]+)\]\s*"#)

    /// Nil when `line` is not a headline (stars followed by a space, or stars alone).
    init?(_ line: Substring, keywords: OrgTodoKeywords) {
        let stars = line.prefix { $0 == "*" }
        let rest = line.dropFirst(stars.count)
        guard !stars.isEmpty, rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        level = stars.count
        var text = rest.trimmingCharacters(in: .whitespaces)
        let first = text.prefix { !$0.isWhitespace }
        if !first.isEmpty, keywords.all.contains(String(first)) {
            keyword = String(first)
            text = String(text.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
        } else {
            keyword = nil
        }
        priority = Self.capture(Self.priorityPattern, in: &text)
        tags = Self.capture(Self.tagsPattern, in: &text)?.split(separator: ":").map(String.init) ?? []
        title = text.trimmingCharacters(in: .whitespaces)
    }

    /// Removes the pattern's whole match from `text` and returns its first group.
    private static func capture(_ regex: NSRegularExpression?, in text: inout String) -> String? {
        let ns = text as NSString
        guard let match = regex?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let value = ns.substring(with: match.range(at: 1))
        text = ns.replacingCharacters(in: match.range, with: "")
        return value
    }
}
