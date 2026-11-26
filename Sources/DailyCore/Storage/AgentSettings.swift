import Foundation

/// How the durable Assistant keeps state and writes: saved chats, long-term memory, routines and vault writes.
/// Saved as `agent` in `settings.json` and editable in Settings → AI → Agent. A missing or mistyped key keeps
/// its default and every number is clamped. Luuna and Org stay read-only whatever these say.
public struct AgentSettings: Codable, Equatable, Sendable {
    /// Who approves a vault change the Assistant makes.
    public enum WriteApproval: String, Codable, CaseIterable, Sendable {
        /// Every change waits in the review queue until the user applies it.
        case review
        /// New notes and appends inside `autoApplyFolders` apply at once; edits and everything else wait.
        case autoApplyFolders = "auto-folders"
        /// New notes, appends and edits anywhere in scope apply at once.
        case autoApplyAll = "auto-all"
    }

    /// Offer the vault write tools (`create_note`, `edit_note`, `append_to_note`).
    public var vaultWrites: Bool
    public var writeApproval: WriteApproval
    /// Vault-relative folders where `auto-folders` applies new notes and appends without review.
    public var autoApplyFolders: [String]
    /// Most changes one run may auto-apply; later ones in the same run wait for review.
    public var maxAutoWritesPerRun: Int
    /// Largest note, in UTF-8 bytes, the Assistant may create or produce by an edit.
    public var maxNoteBytes: Int
    /// Save conversations (encrypted) so they survive quitting and can be resumed.
    public var saveConversations: Bool
    /// Saved conversations older than this many days are deleted at launch.
    public var conversationRetentionDays: Int
    /// Offer the `memory` tool and its app-owned memory folder.
    public var memory: Bool
    /// Run the user's scheduled routines while the app is open.
    public var routines: Bool

    public static let autoWriteRange = 0...50
    public static let noteByteRange = 4_096...1_000_000
    public static let retentionRange = 1...3_650

    public init(
        vaultWrites: Bool = true,
        writeApproval: WriteApproval = .autoApplyFolders,
        autoApplyFolders: [String] = ["00-inbox"],
        maxAutoWritesPerRun: Int = 10,
        maxNoteBytes: Int = 200_000,
        saveConversations: Bool = true,
        conversationRetentionDays: Int = 180,
        memory: Bool = true,
        routines: Bool = true
    ) {
        self.vaultWrites = vaultWrites
        self.writeApproval = writeApproval
        self.autoApplyFolders = autoApplyFolders
        self.maxAutoWritesPerRun = maxAutoWritesPerRun
        self.maxNoteBytes = maxNoteBytes
        self.saveConversations = saveConversations
        self.conversationRetentionDays = conversationRetentionDays
        self.memory = memory
        self.routines = routines
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AgentSettings()
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys, _ defaultValue: T) -> T {
            (try? c.decodeIfPresent(type, forKey: key)) ?? defaultValue
        }
        self.init(
            vaultWrites: value(Bool.self, .vaultWrites, fallback.vaultWrites),
            writeApproval: value(WriteApproval.self, .writeApproval, fallback.writeApproval),
            autoApplyFolders: value([String].self, .autoApplyFolders, fallback.autoApplyFolders),
            maxAutoWritesPerRun: value(Int.self, .maxAutoWritesPerRun, fallback.maxAutoWritesPerRun),
            maxNoteBytes: value(Int.self, .maxNoteBytes, fallback.maxNoteBytes),
            saveConversations: value(Bool.self, .saveConversations, fallback.saveConversations),
            conversationRetentionDays: value(Int.self, .conversationRetentionDays, fallback.conversationRetentionDays),
            memory: value(Bool.self, .memory, fallback.memory),
            routines: value(Bool.self, .routines, fallback.routines))
        self = validated
    }

    /// These settings with numbers in range and folders normalized: trimmed of spaces and slashes, without
    /// `..` or hidden components, de-duplicated and sorted.
    public var validated: AgentSettings {
        func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
            min(max(value, range.lowerBound), range.upperBound)
        }
        var copy = self
        copy.maxAutoWritesPerRun = clamp(maxAutoWritesPerRun, Self.autoWriteRange)
        copy.maxNoteBytes = clamp(maxNoteBytes, Self.noteByteRange)
        copy.conversationRetentionDays = clamp(conversationRetentionDays, Self.retentionRange)
        let folders = autoApplyFolders.compactMap(Self.normalizedFolder)
        copy.autoApplyFolders = Array(Set(folders)).sorted()
        return copy
    }

    /// `folder` as a clean vault-relative path, or nil when it is empty or could leave the vault.
    public static func normalizedFolder(_ folder: String) -> String? {
        let parts = folder.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").map(String.init)
            .filter { !$0.isEmpty && $0 != "." }
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0.hasPrefix(".") }) else { return nil }
        return parts.joined(separator: "/")
    }

    /// True when `path` (vault-relative) lies inside one of `autoApplyFolders`.
    public func isAutoApplyFolder(_ path: String) -> Bool {
        autoApplyFolders.contains { path.hasPrefix($0 + "/") }
    }
}
