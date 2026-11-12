import AppKit
import Combine
import DailyCore
import Foundation

// The federated, read-only sources: Open Loops, Projects and Luuna. They refresh on app activation and on a vault
// change (no polling), and every store discards results that arrive for an earlier vault, refresh or connection.
extension AppModel {
    /// Re-read Open Loops (vault files and Reminders), Projects and Luuna.
    func refreshSources() {
        Task { await openLoops.refresh() }
        Task { await projects.refresh() }
        Task { await luuna.refresh() }
    }

    /// Point the vault readers at the current vault whenever it changes, and re-read. The current vault is applied
    /// at once; it is read now only when `refreshNow` (tests refresh explicitly).
    func observeVault(refreshNow: Bool) {
        applyVaultRoot(vaultSession.vault?.root)
        if refreshNow { refreshSources() }
        vaultSubscription = vaultSession.$state
            .map { state -> URL? in
                if case .available(let url) = state { return url }
                return nil
            }
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] root in
                guard let self else { return }
                applyVaultRoot(root)
                refreshSources()
            }
    }

    private func applyVaultRoot(_ root: URL?) {
        openLoops.setVaultRoot(root)
        projects.setVaultRoot(root)
    }

    /// Route to an external loop's owner file: Org files open in Notes; Seeds and Plot files are revealed in
    /// Finder. Never writes. Local tasks and reminders have no file: act on them through `TaskStore` and
    /// `RemindersService` (`OpenLoopsStore.task(for:)` / `reminder(for:)`). Returns false when there is nothing
    /// to open.
    @discardableResult
    func openSource(of loop: OpenLoop) -> Bool {
        switch loop.sourceLink {
        case .note(let path, _):
            openNote(path)
            return true
        case .vaultFile(let path, _):
            guard let vault = vaultSession.vault, let url = try? vault.resolve(relativePath: path) else { return false }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        case .localTask, .reminder, nil:
            return false
        }
    }

    // MARK: Luuna

    /// Validate and save a Luuna runtime origin and token, then reconnect. `token` nil keeps the saved token; an
    /// empty token removes it from the Keychain. Returns why it was refused, or nil once saved and reconnected.
    /// Nothing is saved for an origin that is not an HTTP loopback address.
    func connectLuuna(origin text: String, token: String?) -> String? {
        let origin: LuunaOrigin
        do {
            origin = try LuunaOrigin(validating: text)
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "That is not a valid runtime URL."
        }
        let savedToken: String?
        switch luunaSettings.save(origin: origin, token: token) {
        case .success(let token): savedToken = token
        case .failure(let failure): return failure.message
        }
        luunaSettingsNotice = nil
        luuna.connect(origin: origin, token: savedToken)
        Task { await luuna.refresh() }
        return nil
    }
}

/// The saved Luuna connection: the origin in `luuna-host.json` (app folder) and the bearer token in the Keychain.
/// The token is never written to a file.
struct LuunaSettings {
    struct Saved {
        var origin: LuunaOrigin
        var token: String?
        /// Something the user should know: a host file moved aside or unreadable, or an unreadable token.
        var notice: String?
    }

    struct Failure: Error {
        let message: String
    }

    let host: LuunaHostAccessStore
    let keys: APIKeyStore

    init(directory: WorkspaceDirectory, keys: APIKeyStore) {
        host = LuunaHostAccessStore(directory: directory)
        self.keys = keys
    }

    /// The saved origin (the standard origin when none is saved or it cannot be read) and token.
    func load() -> Saved {
        var notices: [String] = []
        var origin = LuunaOrigin.standard
        do {
            let load = try host.load()
            if let access = load.value { origin = access.origin }
            if load.movedAside != nil {
                notices.append("The saved Luuna runtime URL could not be read and was moved aside.")
            }
        } catch {
            Log.luuna.error(
                "Luuna host file could not be read: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            notices.append("The saved Luuna runtime URL could not be read: \(error.localizedDescription)")
        }
        var token: String?
        do {
            token = try keys.read()
        } catch {
            Log.luuna.error("Luuna token could not be read: \(Log.code(error), privacy: .public)")
            notices.append("The Luuna token could not be read from the Keychain.")
        }
        return Saved(origin: origin, token: token, notice: notices.isEmpty ? nil : notices.joined(separator: " "))
    }

    /// Saves `origin`, then the token: nil keeps the saved one, empty removes it. Returns the token now in effect.
    func save(origin: LuunaOrigin, token: String?) -> Result<String?, Failure> {
        do {
            try host.save(LuunaHostAccess(origin: origin))
        } catch {
            Log.luuna.error(
                "Luuna origin could not be saved: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            return .failure(Failure(message: "The runtime URL could not be saved: \(error.localizedDescription)"))
        }
        do {
            guard let token else { return .success(try keys.read()) }
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            try keys.save(trimmed)
            return .success(trimmed.isEmpty ? nil : trimmed)
        } catch {
            Log.luuna.error("Luuna token could not be stored: \(Log.code(error), privacy: .public)")
            return .failure(
                Failure(message: "The token could not be stored in the Keychain: \(error.localizedDescription)"))
        }
    }
}
