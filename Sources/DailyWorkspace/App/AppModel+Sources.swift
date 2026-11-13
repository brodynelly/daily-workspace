import Combine
import DailyCore
import Foundation

// The federated, read-only sources: Open Loops, Projects and Luuna. They refresh on app activation and on a vault
// change (no polling), and every store discards results that arrive for an earlier vault, refresh or connection.
extension AppModel {
    /// Re-read Reminders and opted-in Mail open loops, project hubs and Luuna.
    func refreshSources() {
        Task { await openLoops.refresh() }
        Task { await projects.refresh() }
        guard !luunaCredentialLoading else { return }
        Task { await luuna.refresh() }
        Task { await luunaWork.refreshGlobalHome() }
        Task { await luunaWork.refresh() }
    }

    /// Point the vault readers at the current vault and track Mail consent. Preference publishers emit before the
    /// stored property changes, so use the value they deliver to clear private rows synchronously on opt-out.
    func observeVault(refreshNow: Bool) {
        applyVaultRoot(vaultSession.vault?.root)
        openLoops.setMailEnabled(preferences.mailEnabled)
        if refreshNow { refreshSources() }
        luunaWorkSubscription = projects.$detail
            .map { $0?.association?.luuna }
            .removeDuplicates()
            .sink { [weak self] binding in
                guard let self else { return }
                bindLuunaWork(binding)
            }
        vaultSubscription = vaultSession.$state
            .map { state -> URL? in
                if case .available(let url) = state { return url }
                return nil
            }
            .combineLatest(preferences.$mailEnabled)
            .dropFirst()
            .removeDuplicates { earlier, later in
                earlier.0?.standardizedFileURL == later.0?.standardizedFileURL && earlier.1 == later.1
            }
            .sink { [weak self] root, mailEnabled in
                guard let self else { return }
                let vaultChanged = root?.standardizedFileURL != openLoops.vaultRoot?.standardizedFileURL
                applyVaultRoot(root)
                let consentChanged = openLoops.mailEnabled != mailEnabled
                openLoops.setMailEnabled(mailEnabled)
                if vaultChanged {
                    refreshSources()
                } else if consentChanged && mailEnabled {
                    Task { await self.openLoops.refreshMail() }
                }
            }
    }

    private func applyVaultRoot(_ root: URL?) {
        openLoops.setVaultRoot(root)
        projects.setVaultRoot(root)
    }

    /// A binding is explicit and authority-scoped: an ID from another origin must never be queried here.
    private func bindLuunaWork(_ binding: LuunaProjectBinding?) {
        let projectID = binding.flatMap { $0.origin == luuna.origin ? $0.projectID : nil }
        luunaWork.connect(origin: luuna.origin, token: luunaWorkToken, projectID: projectID)
        if projectID != nil { Task { await luunaWork.refresh() } }
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
        luunaCredentialGeneration += 1
        luunaCredentialLoading = false
        luunaSettingsNotice = nil
        luuna.connect(origin: origin, token: savedToken)
        luunaWorkToken = savedToken
        bindLuunaWork(projects.detail?.association?.luuna)
        Task { await luunaWork.refreshGlobalHome() }
        Task { await luuna.refresh() }
        return nil
    }

    /// A Keychain service may wait for its security daemon even with interaction disabled. Never
    /// let that wait block the app's main window or private control socket during cold launch.
    func loadLuunaCredentialsInBackground() {
        let keys = luunaSettings.keys
        let origin = luuna.origin
        let generation = luunaCredentialGeneration
        Task.detached { [weak self] in
            let token: String?
            let notice: String?
            do {
                token = try keys.read()
                notice = nil
            } catch {
                token = nil
                notice = "The Luuna token could not be read from the Keychain."
                Log.luuna.error("Luuna token could not be read: \(Log.code(error), privacy: .public)")
            }
            await self?.applyLuunaCredentialLoad(token: token, notice: notice, origin: origin, generation: generation)
        }
    }

    private func applyLuunaCredentialLoad(
        token: String?, notice: String?, origin: LuunaOrigin, generation: Int
    ) {
        guard luunaCredentialGeneration == generation else { return }
        luunaCredentialLoading = false
        if let notice {
            luunaSettingsNotice = [luunaSettingsNotice, notice].compactMap { $0 }.joined(separator: " ")
        }
        luuna.connect(origin: origin, token: token)
        luunaWorkToken = token
        bindLuunaWork(projects.detail?.association?.luuna)
        Task { await luuna.refresh() }
        Task { await luunaWork.refreshGlobalHome() }
        Task { await luunaWork.refresh() }
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
        var saved = loadHost()
        do {
            saved.token = try keys.read()
        } catch {
            Log.luuna.error("Luuna token could not be read: \(Log.code(error), privacy: .public)")
            saved.notice = [saved.notice, "The Luuna token could not be read from the Keychain."]
                .compactMap { $0 }.joined(separator: " ")
        }
        return saved
    }

    /// Local host metadata is quick to read; the Keychain credential is loaded separately on launch.
    func loadHost() -> Saved {
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
        return Saved(origin: origin, token: nil, notice: notices.isEmpty ? nil : notices.joined(separator: " "))
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
