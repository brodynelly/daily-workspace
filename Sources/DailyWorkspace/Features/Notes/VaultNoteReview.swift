import DailyCore
import Foundation

/// One immutable, fully previewed Markdown change. A model cannot create or commit this value; the
/// review UI constructs it from the user's exact target and editable draft before each confirmation.
@MainActor
struct VaultNoteReview {
    enum Mode { case append, replace, quickNotes }
    enum Requirement { case existing, new, either }

    let path: String
    let before: String?
    let after: String
    let root: URL
    let snapshot: FileSnapshot?

    static let quickNotesPath = "02-areas/personal-development/quick-notes.md"

    static func prepare(
        model: AppModel, path: String, draft: String, mode: Mode, requirement: Requirement
    ) throws -> VaultNoteReview {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultError.io("Enter note text before reviewing.")
        }
        let text = draft
        let (vault, allowed) = try target(model: model, path: path)
        let exists = vault.exists(allowed.url)
        switch requirement {
        case .existing where !exists: throw VaultError.missing
        case .new where exists: throw VaultError.alreadyExists
        default: break
        }
        let loaded = exists ? try vault.load(allowed.url) : nil
        if model.document.relativePath == allowed.path, model.document.saveState != .clean {
            throw VaultError.io("Save or resolve the open note in Notes before reviewing this change.")
        }
        if mode == .quickNotes, allowed.path != quickNotesPath || loaded == nil {
            throw VaultError.io("Quick Notes must be the selected existing inbox note.")
        }
        let after: String
        switch mode {
        case .append:
            after = loaded.map { NoteVault.appending(text + "\n", to: $0.text) } ?? text + "\n"
        case .replace:
            after = text + (text.hasSuffix("\n") ? "" : "\n")
        case .quickNotes:
            guard let original = loaded?.text,
                let capture = original.range(of: "(?m)^## Capture\\r?$", options: .regularExpression),
                let next = original.range(of: "\n## ", range: capture.upperBound..<original.endIndex)
            else { throw VaultError.io("Quick Notes no longer has its Capture section; review it in Notes first.") }
            let newline = original.contains("\r\n") ? "\r\n" : "\n"
            let item = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            let prefix = String(original[..<next.lowerBound])
            let suffix = String(original[next.lowerBound...])
            after = NoteVault.appending("- \(item)\(newline)", to: prefix) + suffix
        }
        return VaultNoteReview(
            path: allowed.path, before: loaded?.text, after: after, root: vault.root,
            snapshot: loaded?.snapshot)
    }

    /// Called only by the Confirm button. A changed vault, scope, parent, open editor or disk snapshot
    /// refuses the save; the review sheet keeps the user's draft for a new preview.
    func commit(model: AppModel) throws {
        let (vault, allowed) = try Self.target(model: model, path: path)
        guard vault.root == root, allowed.path == path else { throw VaultError.conflict }
        if let snapshot {
            if model.document.relativePath == path {
                guard model.document.text == before else { throw VaultError.conflict }
                try model.document.applyReviewed(after, expecting: snapshot)
            } else {
                _ = try vault.save(after, to: allowed.url, expecting: snapshot)
            }
        } else {
            _ = try vault.create(allowed.url, initialText: after, requireExistingParent: true)
        }
        model.preferences.rememberRecent(path)
        model.assistantContext.invalidateNotes()
    }

    private static func target(model: AppModel, path: String) throws -> (NoteVault, VaultReadPolicy.Allowed) {
        guard case .available = model.vaultSession.state, let vault = model.vaultSession.vault else {
            throw VaultError.io("Choose and authorize an Obsidian vault before saving.")
        }
        let allowed = try VaultReadPolicy.resolve(path, root: vault.root, scope: .standard)
        guard path == allowed.path, allowed.url.pathExtension.lowercased() == "md" else {
            throw VaultError.io("Choose an exact, visible Markdown path inside the selected vault.")
        }
        let parent = allowed.url.deletingLastPathComponent()
        var directory: ObjCBool = false
        guard parent != vault.root, FileManager.default.fileExists(atPath: parent.path, isDirectory: &directory),
            directory.boolValue
        else { throw VaultError.io("The chosen note folder must already exist inside the vault.") }
        return (vault, allowed)
    }
}
