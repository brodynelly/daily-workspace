import DailyCore
import Foundation

/// The note open in the editor: loading, debounced autosave, external-change detection and conflict
/// resolution. Never writes text it did not load, and never discards a version without stashing it first.
@MainActor
final class NoteDocument: ObservableObject {
    enum SaveState: Equatable {
        case clean, dirty, saving, conflict
        case failed(String)
    }

    enum OpenResult: Equatable {
        case opened, alreadyOpen, missing
    }

    @Published private(set) var url: URL?
    @Published private(set) var text = ""
    @Published private(set) var saveState: SaveState = .clean
    @Published private(set) var message: String?

    private(set) var vault: NoteVault?
    private var snapshot: FileSnapshot?
    private var saveTask: Task<Void, Never>?
    private let recovery: RecoveryStoring
    private let autosaveDelay: Duration

    init(recovery: RecoveryStoring, autosaveDelay: Duration = .milliseconds(800)) {
        self.recovery = recovery
        self.autosaveDelay = autosaveDelay
    }

    var recoveryFolder: URL? { recovery.folder }
    var isConflict: Bool { saveState == .conflict }

    var canSave: Bool {
        switch saveState {
        case .dirty, .failed: return true
        default: return false
        }
    }

    /// Vault-relative path of the open note.
    var relativePath: String? {
        guard let url else { return nil }
        return vault?.relativePath(of: url)
    }

    /// Point the document at another vault. Closes the open note when the vault root changes.
    func attach(_ newVault: NoteVault?) {
        guard newVault?.root != vault?.root else { return }
        saveTask?.cancel()
        vault = newVault
        url = nil
        text = ""
        snapshot = nil
        saveState = .clean
        message = nil
    }

    /// Show a status line above the editor (or clear it with nil).
    func post(_ message: String?) {
        self.message = message
    }

    /// Load `relativePath` into the editor. The caller must call `flushBeforeSwitching()` first.
    @discardableResult
    func open(relativePath: String, createIfMissing: Bool, initialText: String) throws -> OpenResult {
        guard let vault else { throw VaultError.missing }
        let target = try vault.resolve(relativePath: relativePath)
        if target == url {
            message = nil
            return .alreadyOpen
        }
        let loaded: LoadedNote
        if vault.exists(target) {
            loaded = try vault.load(target)
        } else if createIfMissing {
            loaded = try vault.create(target, initialText: initialText)
        } else {
            return .missing
        }
        saveTask?.cancel()
        url = target
        text = loaded.text
        snapshot = loaded.snapshot
        saveState = .clean
        message = nil
        return .opened
    }

    /// Save pending edits. Returns false when the note needs the user's attention (conflict or failed save).
    func flushBeforeSwitching() -> Bool {
        if saveState == .dirty || saveState == .saving { saveNow() }
        if saveState == .conflict {
            message = "Resolve the conflict on the open note first."
            return false
        }
        if case .failed = saveState {
            message = "The note could not be saved. Retry saving before opening another note."
            return false
        }
        return true
    }

    func userEdited(_ newText: String) {
        guard newText != text else { return }
        text = newText
        guard saveState != .conflict else { return }
        saveState = .dirty
        scheduleSave()
    }

    /// Append a block to the open note and save at once. Returns true only when the block reached disk;
    /// otherwise the editor text is left as it was, so a retry cannot duplicate the block.
    func append(_ block: String) -> Bool {
        guard url != nil, saveState != .conflict else { return false }
        let previous = text
        text = NoteVault.appending(block, to: text)
        saveState = .dirty
        saveNow()
        guard saveState == .clean else {
            // Atomic writes leave the disk untouched on failure; drop the block, keep the failure state.
            text = previous
            return false
        }
        return true
    }

    /// Apply a reviewed full-note preview through the open editor instead of writing behind it.
    /// The preview's snapshot must still be the editor's and the disk's version.
    func applyReviewed(_ reviewedText: String, expecting expected: FileSnapshot) throws {
        guard saveState == .clean, snapshot == expected else { throw VaultError.conflict }
        checkExternalChange()
        guard saveState == .clean, snapshot == expected else { throw VaultError.conflict }
        userEdited(reviewedText)
        saveNow()
        switch saveState {
        case .clean: return
        case .conflict: throw VaultError.conflict
        case .failed(let reason): throw VaultError.io(reason)
        default: throw VaultError.io("The note was not saved.")
        }
    }

    func saveNow() {
        saveTask?.cancel()
        guard let vault, let url, let snap = snapshot else { return }
        switch saveState {
        case .dirty, .failed: break
        default: return
        }
        saveState = .saving
        do {
            snapshot = try vault.save(text, to: url, expecting: snap)
            saveState = .clean
        } catch VaultError.conflict, VaultError.missing {
            Log.notes.notice("Save paused: the note changed on disk")
            saveState = .conflict
        } catch {
            Log.notes.error(
                "Save failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            saveState = .failed(error.localizedDescription)
        }
    }

    /// Pick up edits made by Obsidian, a sync client or anything else.
    func checkExternalChange() {
        guard let vault, let url, let snap = snapshot else { return }
        switch saveState {
        case .saving, .conflict: return
        default: break
        }
        do {
            guard let current = try vault.currentSnapshot(of: url) else {
                if saveState != .clean {
                    saveState = .conflict
                } else {
                    message = "The open note was removed from the vault."
                }
                return
            }
            guard current != snap else { return }
            if saveState == .clean {
                let loaded = try vault.load(url)
                text = loaded.text
                snapshot = loaded.snapshot
                message = "Updated from disk: the note changed outside the app."
                Log.notes.info("Reloaded note after an external change")
            } else {
                Log.notes.notice("External change while editing: conflict")
                saveState = .conflict
            }
        } catch {
            // Transient read failure (file locked mid-sync): try again on the next poll.
            Log.notes.debug(
                "External-change check failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
        }
    }

    /// Conflict choice 1: take the disk version. The local version goes to the recovery folder first.
    func resolveConflictByReloading() {
        guard let vault, let url else { return }
        do {
            try recovery.stash(text, label: "my-version")
        } catch {
            Log.notes.error(
                "Recovery stash failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            message =
                "Your version could not be saved to the recovery folder, so it was kept. \(error.localizedDescription)"
            return
        }
        do {
            let loaded = try vault.load(url)
            text = loaded.text
            snapshot = loaded.snapshot
            saveState = .clean
            message = "Reloaded from disk. Your version was saved to the recovery folder."
        } catch {
            message = error.localizedDescription
        }
    }

    /// Conflict choice 2: keep local text. The disk version goes to the recovery folder first.
    func resolveConflictByKeepingMine() {
        guard let vault, let url else { return }
        do {
            if vault.exists(url) {
                try recovery.stash(try vault.load(url).text, label: "disk-version")
            }
        } catch {
            Log.notes.error(
                "Recovery stash failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            message =
                "The disk version could not be saved to the recovery folder, so nothing was overwritten. \(error.localizedDescription)"
            return
        }
        do {
            if let current = try vault.currentSnapshot(of: url) {
                snapshot = current
            } else {
                // The file was deleted: recreate it from the local text.
                snapshot = try vault.create(url, initialText: text).snapshot
            }
            saveState = .dirty
            saveNow()
            switch saveState {
            case .clean: message = "Kept your version. The other version was saved to the recovery folder."
            case .failed(let why): message = "Your version could not be saved: \(why)"
            default: message = "The note changed again on disk. Choose a version again."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = autosaveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
