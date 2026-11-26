import DailyCore
import Foundation

/// The note open in the editor, so an Assistant change to it goes through the editor and never races it.
@MainActor
protocol OpenNoteEditing: AnyObject {
    var relativePath: String? { get }
    var text: String { get }
    var hasUnsavedEdits: Bool { get }
    func applyReviewed(_ reviewedText: String, expecting expected: FileSnapshot) throws
}

extension NoteDocument: OpenNoteEditing {
    var hasUnsavedEdits: Bool { saveState != .clean }
}

extension ToolFailure: LocalizedError {
    var errorDescription: String? { message }
}

/// The Assistant's vault changes: computed against the note on disk, applied at once or queued for review per
/// Settings → AI → Agent, saved with their before and after text (`vault-changes.json`), audited by hash
/// (`vault-journal.jsonl`) and undoable while the note still holds what the Assistant wrote.
///
/// Every write keeps the vault invariants: an exact, visible, in-scope Markdown path in an existing folder (never
/// the vault root), atomic saves that refuse a note changed since it was read, no deletes, renames or moves, and
/// the open editor's unsaved edits are never overwritten.
@MainActor
final class VaultChanges: ObservableObject {
    @Published private(set) var changes: [VaultChange] = []
    /// Set when the queue or journal could not be read or saved.
    @Published private(set) var storageError: String?

    /// Called after a change reaches disk (applied or undone), e.g. to refresh the note index.
    var onWrite: (() -> Void)?

    private let store: VaultChangeStore?
    private let vault: () -> NoteVault?
    private weak var editor: (any OpenNoteEditing)?
    private let settings: () -> AgentSettings
    private let scope: VaultScope
    private let now: () -> Date
    /// Changes applied without review per run, against `maxAutoWritesPerRun`.
    private var autoApplied: [UUID: Int] = [:]

    init(
        store: VaultChangeStore?, vault: @escaping () -> NoteVault?, editor: (any OpenNoteEditing)?,
        settings: @escaping () -> AgentSettings, scope: VaultScope = .standard, now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.vault = vault
        self.editor = editor
        self.settings = settings
        self.scope = scope
        self.now = now
        do {
            changes = try store?.load() ?? []
        } catch {
            Log.assistant.error("The vault change queue could not be read: \(Log.code(error), privacy: .public)")
            storageError = "The Assistant's change history could not be read."
        }
    }

    /// Changes waiting for review, oldest first.
    var pending: [VaultChange] { changes.filter { $0.status == .pending }.sorted { $0.createdAt < $1.createdAt } }
    /// Finished changes, newest first.
    var history: [VaultChange] { changes.filter { $0.status != .pending }.sorted { $0.updatedAt > $1.updatedAt } }

    // MARK: Proposals

    /// Compute `request` against the note and apply or queue it. A second change to a note that already has one
    /// waiting is folded into it, so review always shows one before/after per note.
    func propose(_ request: VaultChangeRequest, summary: String, run: AgentRunContext) throws -> VaultChangeOutcome {
        let limits = settings()
        guard limits.vaultWrites else { throw ToolFailure("Vault writes are off in Settings → AI → Agent.") }
        let (vault, allowed) = try target(request.path)
        if let editor, editor.relativePath == allowed.path, editor.hasUnsavedEdits {
            throw ToolFailure("\(allowed.path) is open in Notes with unsaved edits. Try again after Brody saves it.")
        }
        let onDisk = try vault.exists(allowed.url) ? load(vault, allowed.url) : nil
        let vaultID = Self.identity(of: vault)
        var queued = pending.first { $0.path == allowed.path && $0.vault == vaultID }
        if let stale = queued, !Self.sameBytes(stale.before, onDisk) {
            fail(stale.id, reason: "The note changed in the vault after this change was proposed.")
            queued = nil
        }
        let base = queued?.after ?? onDisk
        let (kind, after) = try Self.compute(request, base: base, path: allowed.path)
        guard after.utf8.count <= limits.maxNoteBytes else {
            throw ToolFailure("The note would exceed \(limits.maxNoteBytes) bytes. Split it into smaller notes.")
        }
        guard !Self.sameBytes(after, base) else {
            throw ToolFailure("That change leaves \(allowed.path) exactly as it is.")
        }
        let change: VaultChange
        let event: VaultJournalEntry.Event
        if var merged = queued {
            merged.kind = merged.kind == .create ? .create : (merged.kind == .edit || kind == .edit ? .edit : .append)
            merged.after = after
            merged.summary = [merged.summary, summary].filter { !$0.isEmpty }.joined(separator: " ")
            merged.updatedAt = now()
            change = merged
            event = .updated
        } else {
            change = VaultChange(
                kind: kind, path: allowed.path, before: onDisk, after: after, summary: summary, origin: run.origin,
                conversationID: run.conversationID, vault: vaultID, createdAt: now())
            event = .proposed
        }
        // The audit event and the before/after text must be on disk before anything can reach the vault.
        try recordDurably(change, event)
        let counts = change.lineCounts
        // A change already waiting keeps waiting: whatever made it need review still holds after a merge.
        let reason =
            queued == nil ? reviewReason(change, run: run, limits: limits) : "it joins a change already waiting"
        if let reason {
            return VaultChangeOutcome(
                changeID: change.id.uuidString, status: .awaitingReview, path: change.path,
                linesAdded: counts.added, linesRemoved: counts.removed,
                note: "Queued for Brody's review (\(reason)). It is not in the vault yet; say so.")
        }
        do {
            try apply(change.id, actor: "policy")
        } catch {
            throw ToolFailure("\(change.path) could not be changed: \(Self.describe(error))")
        }
        autoApplied[run.id, default: 0] += 1
        return VaultChangeOutcome(
            changeID: change.id.uuidString, status: .applied, path: change.path, linesAdded: counts.added,
            linesRemoved: counts.removed, note: "Applied. Brody can review or undo it in the Assistant's Changes list.")
    }

    // MARK: Review actions

    /// Write a pending change. Refused, and marked failed, when the note no longer matches what it was computed
    /// against. `actor` is `user` for a review click and `policy` for an automatic apply.
    func apply(_ id: UUID, actor: String = "user") throws {
        guard var change = changes.first(where: { $0.id == id }), change.status == .pending else {
            throw VaultError.io("This change is no longer waiting for review.")
        }
        do {
            let (vault, allowed) = try target(change.path, for: change)
            try write(change.after, replacing: change.before, at: allowed, in: vault)
        } catch {
            fail(id, reason: Self.describe(error))
            throw error
        }
        change.status = .applied
        change.autoApplied = actor == "policy"
        change.appliedAt = now()
        change.updatedAt = now()
        change.failure = nil
        upsert(change)
        record(change, .applied, actor: actor)
        persist()
        onWrite?()
    }

    func reject(_ id: UUID) {
        guard var change = changes.first(where: { $0.id == id }), change.status == .pending else { return }
        change.status = .rejected
        change.updatedAt = now()
        upsert(change)
        record(change, .rejected, actor: "user")
        persist()
    }

    /// Put the note back as it was before an applied change, only if it still holds exactly what was written.
    func undo(_ id: UUID) throws {
        guard var change = changes.first(where: { $0.id == id }), change.canUndo, let before = change.before else {
            throw VaultError.io("Only an applied change to an existing note can be undone.")
        }
        let (vault, allowed) = try target(change.path, for: change)
        do {
            try write(before, replacing: change.after, at: allowed, in: vault)
        } catch VaultError.conflict {
            throw VaultError.io("\(change.path) changed after the Assistant wrote it, so it was left as it is.")
        }
        change.status = .undone
        change.updatedAt = now()
        upsert(change)
        record(change, .undone, actor: "user")
        persist()
        onWrite?()
    }

    // MARK: Writing

    /// An exact, visible, in-scope Markdown path whose folder exists and is not the vault root. With `change`,
    /// the selected vault must be the one it was proposed in.
    private func target(_ path: String, for change: VaultChange? = nil) throws -> (NoteVault, VaultReadPolicy.Allowed) {
        guard let vault = vault() else { throw ToolFailure("No vault is selected and authorized.") }
        if let change, change.vault != Self.identity(of: vault) {
            throw ToolFailure("This change was proposed in another vault. Select that vault to apply or undo it.")
        }
        let allowed: VaultReadPolicy.Allowed
        do {
            allowed = try VaultReadPolicy.resolve(path, root: vault.root, scope: scope)
        } catch let failure as ToolFailure {
            throw ToolFailure(failure.message.replacingOccurrences(of: "was not read", with: "can't be changed"))
        }
        guard allowed.url.pathExtension.lowercased() == "md" else {
            throw ToolFailure("Only Markdown notes (.md) can be written.")
        }
        let parent = allowed.url.deletingLastPathComponent()
        var isFolder: ObjCBool = false
        guard parent.standardized != vault.root.standardized,
            FileManager.default.fileExists(atPath: parent.path, isDirectory: &isFolder), isFolder.boolValue
        else {
            throw ToolFailure("Notes go in an existing folder inside the vault, never the vault root.")
        }
        return (vault, allowed)
    }

    private func load(_ vault: NoteVault, _ url: URL) throws -> String {
        do {
            return try vault.load(url).text
        } catch VaultError.notUTF8 {
            throw ToolFailure("That note is not UTF-8 text, so it is left untouched.")
        }
    }

    /// Replace the note's text, or create it when `expected` is nil, through the editor when it is open there.
    private func write(
        _ text: String, replacing expected: String?, at allowed: VaultReadPolicy.Allowed, in vault: NoteVault
    ) throws {
        guard let expected else {
            guard !vault.exists(allowed.url) else { throw VaultError.alreadyExists }
            _ = try vault.create(allowed.url, initialText: text, requireExistingParent: true)
            return
        }
        guard vault.exists(allowed.url) else { throw VaultError.missing }
        let loaded = try vault.load(allowed.url)
        guard Self.sameBytes(loaded.text, expected) else { throw VaultError.conflict }
        if let editor, editor.relativePath == allowed.path {
            guard !editor.hasUnsavedEdits, Self.sameBytes(editor.text, expected) else { throw VaultError.conflict }
            try editor.applyReviewed(text, expecting: loaded.snapshot)
        } else {
            _ = try vault.save(text, to: allowed.url, expecting: loaded.snapshot)
        }
    }

    // MARK: Bookkeeping

    private func upsert(_ change: VaultChange) {
        if let index = changes.firstIndex(where: { $0.id == change.id }) {
            changes[index] = change
        } else {
            changes.append(change)
        }
    }

    private func fail(_ id: UUID, reason: String) {
        guard var change = changes.first(where: { $0.id == id }) else { return }
        change.status = .failed
        change.failure = reason
        change.updatedAt = now()
        upsert(change)
        record(change, .failed, actor: "policy")
        persist()
    }

    /// Journal `event` and save the queue with `change`, or change nothing and throw: used before a write, so a
    /// change never reaches the vault without its audit line and its before/after text.
    private func recordDurably(_ change: VaultChange, _ event: VaultJournalEntry.Event) throws {
        let previous = changes
        upsert(change)
        do {
            try store?.record(
                VaultJournalEntry(
                    at: now(), changeID: change.id, event: event, path: change.path, actor: "assistant",
                    beforeHash: change.beforeHash, afterHash: change.afterHash))
            try store?.save(changes)
        } catch {
            changes = previous
            Log.assistant.error("A vault change could not be recorded: \(Log.code(error), privacy: .public)")
            storageError = "The Assistant's change history could not be saved."
            throw ToolFailure("The change could not be recorded in the app's audit journal, so nothing was written.")
        }
    }

    private func record(_ change: VaultChange, _ event: VaultJournalEntry.Event, actor: String) {
        let entry = VaultJournalEntry(
            at: now(), changeID: change.id, event: event, path: change.path, actor: actor,
            beforeHash: change.beforeHash, afterHash: change.afterHash)
        do {
            try store?.record(entry)
        } catch {
            Log.assistant.error("The vault journal could not be written: \(Log.code(error), privacy: .public)")
            storageError = "The Assistant's change journal could not be written."
        }
    }

    private func persist() {
        do {
            try store?.save(changes)
            // Memory holds no more history than the file does.
            changes = VaultChangeStore.kept(changes)
        } catch {
            Log.assistant.error("The vault change queue could not be saved: \(Log.code(error), privacy: .public)")
            storageError = "The Assistant's change history could not be saved."
        }
    }
}

extension VaultChanges {
    // MARK: Computing changes

    /// The change's kind and the note's full text after it.
    static func compute(_ request: VaultChangeRequest, base: String?, path: String) throws
        -> (VaultChange.Kind, String)
    {
        switch request {
        case .create(_, let text):
            guard base == nil else {
                throw ToolFailure("\(path) already exists. Read it, then use edit_note or append_to_note.")
            }
            return (.create, endsWithNewline(text) ? text : text + "\n")
        case .append(_, let text):
            guard let base else { throw ToolFailure("There is no note at \(path). Use create_note for a new note.") }
            let block = matchingLineEndings(endsWithNewline(text) ? text : text + "\n", of: base)
            return (.append, NoteVault.appending(block, to: base))
        case .edit(_, let old, let new):
            guard let base else { throw ToolFailure("There is no note at \(path). Use create_note for a new note.") }
            let target = matchingLineEndings(old, of: base)
            guard !target.isEmpty else { throw ToolFailure("old_text must not be empty.") }
            let count = base.components(separatedBy: target).count - 1
            guard count == 1 else {
                throw ToolFailure(
                    count == 0
                        ? "old_text was not found in \(path). Read the note again and copy the text exactly."
                        : "old_text appears \(count) times in \(path). Include more surrounding text so it is unique.")
            }
            return (.edit, base.replacingOccurrences(of: target, with: matchingLineEndings(new, of: base)))
        }
    }

    /// Scalars, not Characters: "\r\n" is one Character, so `hasSuffix("\n")` misses a CRLF ending.
    static func endsWithNewline(_ text: String) -> Bool { text.unicodeScalars.last == "\n" }

    /// `text` with the note's line endings, so a CRLF note stays CRLF (vault invariant 1).
    static func matchingLineEndings(_ text: String, of note: String) -> String {
        guard note.contains("\r\n") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
    }

    /// Markdown, Obsidian and HTML links or embeds: `[[note]]`, `![[note]]`, `[text](target)`, `[ref]: target`,
    /// any `scheme://` or `scheme:` URL such as `mailto:`, and HTML tags that load or link something.
    static func addsLinkOrEmbed(_ text: String) -> Bool {
        let patterns = [
            #"\[\["#, #"\]\("#, #"(?m)^\s*\[[^\]]+\]:\s*\S"#, #"(?i)\b[a-z][a-z0-9+.-]*://"#,
            #"(?i)\b(mailto|data|javascript|file|obsidian|tel):"#,
            #"(?i)<\s*(a|img|iframe|script|object|embed|link|video|audio|source|svg|style|form|meta)\b"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Exact text equality, by UTF-8 bytes: Swift `==` treats canonically equivalent text (NFC and NFD) as equal,
    /// which would let a change overwrite a note whose bytes changed since it was read.
    static func sameBytes(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let lhs?, let rhs?): return lhs.utf8.elementsEqual(rhs.utf8)
        default: return false
        }
    }

    /// Which vault a change belongs to.
    static func identity(of vault: NoteVault) -> String { vault.root.standardizedFileURL.path }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "The change could not be written."
    }
}

extension VaultChanges {
    // MARK: Policy

    /// Why `change` must wait for review, or nil when the policy applies it now.
    func reviewReason(_ change: VaultChange, run: AgentRunContext, limits: AgentSettings) -> String? {
        let added = LineDiff(before: change.before ?? "", after: change.after).lines.compactMap { line -> String? in
            if case .added(let text) = line { return text }
            return nil
        }.joined(separator: "\n")
        if limits.writeApproval == .review { return "every change is reviewed" }
        // In every mode a person reviews rewrites of existing text.
        if change.kind == .edit { return "edits to existing text are always reviewed" }
        if limits.writeApproval == .autoApplyFolders, !limits.isAutoApplyFolder(change.path) {
            return "it is outside the auto-apply folders"
        }
        // Links and embeds in model-written text can leak data or pull in other notes when rendered.
        if Self.addsLinkOrEmbed(added) { return "it adds a link or embed" }
        if autoApplied[run.id, default: 0] >= limits.maxAutoWritesPerRun {
            return "this run reached its limit of \(limits.maxAutoWritesPerRun) automatic changes"
        }
        return nil
    }
}
