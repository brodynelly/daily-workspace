import Foundation

/// QAP-style, Foundation-only search over the visible text of a panel row.
/// Build rows when page data changes, then build one query per filter change.
public enum QuickPanelSearch {
    public struct Row {
        public let title: String
        public let detail: String
        public let group: String
        public let badge: String
        public let keys: String
        public let keywords: String
        public let keyNames: [String]

        fileprivate let haystack: String
        fileprivate let normalizedKeyNames: [String]

        /// `shortcutChords` has the shape of QAP's shortcut `keys`: each inner array
        /// is one chord, whose elements are ordered key steps (e.g. [["⌘T"], ["⌥⌘A", "T"]]).
        public init(
            title: String,
            detail: String = "",
            group: String = "",
            badge: String = "",
            keys: String = "",
            keywords: String = "",
            keyNames: [String] = [],
            shortcutChords: [[String]] = []
        ) {
            self.title = title
            self.detail = detail
            self.group = group
            self.badge = badge
            self.keys = keys
            if shortcutChords.isEmpty {
                self.keywords = keywords
                self.keyNames = keyNames
            } else {
                let aliases = QuickPanelSearch.searchKeys(shortcutChords)
                self.keywords = keywords.isEmpty ? aliases.keywords : keywords + " " + aliases.keywords
                self.keyNames = keyNames + aliases.keyNames
            }
            self.haystack = QuickPanelSearch.normalize(
                [title, detail, group, badge, keys, self.keywords].joined(separator: " "))
            self.normalizedKeyNames = self.keyNames.map(QuickPanelSearch.normalize)
        }
    }

    public struct Query {
        private let words: [String]

        public init(_ text: String) {
            words = text.split(whereSeparator: \.isWhitespace).map { QuickPanelSearch.normalize(String($0)) }
        }

        /// Every token must match; for shortcut rows a single-character token must
        /// equal a bare key name, never merely occur in a title or shortcut label.
        public func matches(_ row: Row) -> Bool {
            for word in words {
                if word.count == 1 && !row.normalizedKeyNames.isEmpty {
                    if !row.normalizedKeyNames.contains(word) { return false }
                } else if !row.haystack.contains(word) {
                    return false
                }
            }
            return true
        }
    }

    /// QAP `model.rs::search_keys`: aliases are searchable text, while bare keys
    /// are a separate list for the one-character filter rule.
    public static func searchKeys(_ chords: [[String]]) -> (keywords: String, keyNames: [String]) {
        var words: [String] = []
        var names: [String] = []
        for chord in chords {
            for step in chord {
                let lower = step.lowercased()
                words.append(lower)
                for character in lower {
                    if let alias = keyAliases[character] {
                        words.append(alias)
                    }
                }
                let bare = String(lower.drop(while: { "⌃⌥⇧⌘".contains($0) }))
                words.append(bare)
                names.append(bare)
            }
        }
        return (words.joined(separator: " "), names)
    }

    private static let keyAliases: [Character: String] = [
        "⌃": "ctrl control", "⌥": "alt option opt", "⇧": "shift", "⌘": "cmd command",
        "↩": "return enter", "↵": "return enter", "⇥": "tab", "␣": "space leader",
        "⌫": "backspace", "⌦": "delete", "↑": "up", "↓": "down",
        "←": "left", "→": "right",
    ]

    private static let searchLocale = Locale(identifier: "en_US_POSIX")

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: searchLocale)
    }
}
