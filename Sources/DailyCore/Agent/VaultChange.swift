import Foundation

/// One change the Assistant made or proposed to a vault note, with the exact text before and after.
///
/// A change is computed against the note as it was on disk (`before`); applying it later requires the note to
/// still be exactly `before`, and undoing it requires the note to still be exactly `after`, so neither can
/// overwrite an edit made in Obsidian meanwhile (CONTRIBUTING vault invariant 2).
public struct VaultChange: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// A new note. `before` is nil.
        case create
        /// Exact text replaced inside an existing note.
        case edit
        /// Text added at the end of an existing note.
        case append
    }

    public enum Status: String, Codable, Sendable {
        /// Waiting for the user to apply or reject it.
        case pending
        case applied
        case rejected
        /// Applied, then reverted by the user.
        case undone
        /// Could not be applied (the note changed, the vault moved); `failure` says why.
        case failed
    }

    public let id: UUID
    public var kind: Kind
    /// Vault-relative path of the note.
    public let path: String
    /// The note's text when the change was computed; nil for a new note.
    public let before: String?
    /// The note's full text after the change.
    public var after: String
    /// Why the Assistant made the change, in its words (shown in review, never trusted as fact).
    public var summary: String
    /// `chat` or `routine: <name>`.
    public let origin: String
    /// The saved conversation that proposed it, if any.
    public let conversationID: UUID?
    /// The vault root it was proposed in (standardized path). It is applied and undone only there.
    public let vault: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var status: Status
    /// True when the approval policy applied it without review.
    public var autoApplied: Bool
    public var appliedAt: Date?
    public var failure: String?

    public init(
        id: UUID = UUID(), kind: Kind, path: String, before: String?, after: String, summary: String,
        origin: String, conversationID: UUID?, vault: String? = nil, createdAt: Date, status: Status = .pending
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.before = before
        self.after = after
        self.summary = summary
        self.origin = origin
        self.conversationID = conversationID
        self.vault = vault
        self.createdAt = createdAt
        updatedAt = createdAt
        self.status = status
        autoApplied = false
        appliedAt = nil
        failure = nil
    }

    public var beforeHash: String? { before.map { RestartLedger.sha256(of: Data($0.utf8)) } }
    public var afterHash: String { RestartLedger.sha256(of: Data(after.utf8)) }

    /// Lines added and removed, for a one-line summary such as "+3 −1".
    public var lineCounts: (added: Int, removed: Int) {
        let diff = LineDiff(before: before ?? "", after: after)
        return (diff.added, diff.removed)
    }

    /// A new note cannot be undone by the app: vault files are never deleted (CONTRIBUTING invariant 3).
    public var canUndo: Bool { status == .applied && before != nil }
}

/// A line diff for review: common lines, removed lines and added lines, in order.
public struct LineDiff: Equatable, Sendable {
    public enum Line: Equatable, Sendable {
        case same(String)
        case removed(String)
        case added(String)

        public var isAdded: Bool {
            if case .added = self { return true }
            return false
        }

        public var isRemoved: Bool {
            if case .removed = self { return true }
            return false
        }
    }

    public let lines: [Line]

    /// Above this many lines on either side the diff is shown as one block replaced by another.
    public static let maxLines = 4_000

    public init(before: String, after: String) {
        let old = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let new = after.isEmpty ? [] : after.components(separatedBy: "\n")
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
            old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
        {
            suffix += 1
        }
        let oldMiddle = Array(old[prefix..<(old.count - suffix)])
        let newMiddle = Array(new[prefix..<(new.count - suffix)])
        var result = old[..<prefix].map(Line.same)
        result += Self.middle(oldMiddle, newMiddle)
        result += old[(old.count - suffix)...].map(Line.same)
        lines = result
    }

    public var added: Int { lines.filter(\.isAdded).count }
    public var removed: Int { lines.filter(\.isRemoved).count }

    /// Longest-common-subsequence diff of the changed middle, or a block replacement when it is too large.
    private static func middle(_ old: [String], _ new: [String]) -> [Line] {
        guard !old.isEmpty || !new.isEmpty else { return [] }
        guard old.count <= maxLines, new.count <= maxLines, old.count * new.count <= 4_000_000 else {
            return old.map(Line.removed) + new.map(Line.added)
        }
        var table = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                table[i][j] = old[i] == new[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [Line] = []
        var i = 0
        var j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                result.append(.same(old[i]))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                result.append(.removed(old[i]))
                i += 1
            } else {
                result.append(.added(new[j]))
                j += 1
            }
        }
        result += old[i...].map(Line.removed)
        result += new[j...].map(Line.added)
        return result
    }
}

/// One audit line: what happened to a change, by whom, with hashes only (never note text).
public struct VaultJournalEntry: Codable, Equatable, Sendable {
    public enum Event: String, Codable, Sendable {
        case proposed, updated, applied, rejected, undone, failed
    }

    public let at: Date
    public let changeID: UUID
    public let event: Event
    public let path: String
    /// `assistant`, `user` or `policy` (auto-applied).
    public let actor: String
    public let beforeHash: String?
    public let afterHash: String?

    public init(
        at: Date, changeID: UUID, event: Event, path: String, actor: String, beforeHash: String?,
        afterHash: String?
    ) {
        self.at = at
        self.changeID = changeID
        self.event = event
        self.path = path
        self.actor = actor
        self.beforeHash = beforeHash
        self.afterHash = afterHash
    }
}

/// Saves the change queue and history (`vault-changes.json`) and appends the audit journal
/// (`vault-journal.jsonl`). Pending changes are always kept; finished ones are trimmed to the newest
/// `historyLimit`.
public struct VaultChangeStore: Sendable {
    public let url: URL
    public let journalURL: URL
    public static let historyLimit = 300

    public init(url: URL, journalURL: URL) {
        self.url = url
        self.journalURL = journalURL
    }

    public init(directory: WorkspaceDirectory) {
        self.init(url: directory.vaultChangesURL, journalURL: directory.vaultJournalURL)
    }

    public func load() throws -> [VaultChange] {
        guard let data = try PrivateFile.read(url) else { return [] }
        return try PrivateFile.decoder().decode(Stored.self, from: data).changes
    }

    public func save(_ changes: [VaultChange]) throws {
        let pending = changes.filter { $0.status == .pending }
        let finished = changes.filter { $0.status != .pending }.sorted { $0.updatedAt > $1.updatedAt }
        let kept = pending + finished.prefix(Self.historyLimit)
        try PrivateFile.write(try PrivateFile.encoder().encode(Stored(version: 1, changes: kept)), to: url)
    }

    public func record(_ entry: VaultJournalEntry) throws {
        try PrivateFile.appendLine(try PrivateFile.encoder().encode(entry), to: journalURL)
    }

    private struct Stored: Codable {
        let version: Int
        let changes: [VaultChange]
    }
}
