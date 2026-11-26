import Combine
import DailyCore
import Foundation

// The Assistant's wiring: Settings → AI gates every request, selects a provider/model and sets the runtime limits
// (`assistantRuntime` in settings.json); the vault's root
// AGENTS.md (read-only) is part of the system prompt, so switching vaults starts a new conversation.
extension AppModel {
    /// Follow the enable switch, provider, model ID and vault.
    func observeAssistant() {
        assistant.setEnabled(preferences.assistantEnabled)
        assistant.setProvider(preferences.assistantProvider, model: preferences.selectedAssistantModel)
        assistantKey.setProvider(preferences.assistantProvider)
        applyAssistantRuntime()
        preferences.$assistantRuntime
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] runtime in self?.applyAssistantRuntime(runtime: runtime) }
            .store(in: &assistantSubscriptions)
        preferences.$assistantEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.assistant.setEnabled(enabled)
                if !enabled { self?.routines.cancelRunning() }
            }
            .store(in: &assistantSubscriptions)
        preferences.$assistantProvider
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] provider in
                guard let self else { return }
                let model = provider == .anthropic ? self.preferences.assistantModel : self.preferences.openRouterModel
                self.assistant.setProvider(provider, model: model)
                self.assistantKey.setProvider(provider)
            }
            .store(in: &assistantSubscriptions)
        // Typing a model ID changes it per keystroke; apply it once typing pauses.
        preferences.$assistantModel
            .dropFirst()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] model in
                guard let self, self.preferences.assistantProvider == .anthropic else { return }
                self.assistant.setModel(model)
            }
            .store(in: &assistantSubscriptions)
        preferences.$openRouterModel
            .dropFirst()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] model in
                guard let self, self.preferences.assistantProvider == .openRouter else { return }
                self.assistant.setModel(model)
            }
            .store(in: &assistantSubscriptions)
        // `@Published` emits before the value changes, so the sink uses the emitted root.
        vaultSession.$state
            .map { state -> URL? in
                if case .available(let url) = state { return url }
                return nil
            }
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] root in
                self?.assistantContext.invalidateNotes()
                self?.syncAssistantVaultAgents(vaultRoot: root)
                // A routine started in one vault must not carry its context into another.
                self?.routines.cancelRunning()
            }
            .store(in: &assistantSubscriptions)
        syncAssistantVaultAgents()
    }

    /// Re-read the vault's `AGENTS.md` and start a new conversation if the vault or the file's hash changed since
    /// the current conversation began.
    func syncAssistantVaultAgents() {
        syncAssistantVaultAgents(vaultRoot: vaultSession.vault?.root)
    }

    func syncAssistantVaultAgents(vaultRoot root: URL?) {
        let canonical = root.map { NoteVault(root: $0).root }
        let agents = canonical.flatMap(Self.readVaultAgents)
        let hash = agents.map { RestartLedger.sha256(of: Data($0.utf8)) } ?? "none"
        let fingerprint = "\(canonical?.path ?? "no vault")#\(hash)"
        guard fingerprint != assistantAgentsFingerprint else { return }
        assistantAgentsFingerprint = fingerprint
        assistant.startNewConversation(vaultAgents: agents, identity: fingerprint)
    }

    /// The vault's root `AGENTS.md`, read through `NoteVault` and never written. Nil when absent or unreadable.
    static func readVaultAgents(root: URL) -> String? {
        let vault = NoteVault(root: root)
        do {
            let url = try vault.resolve(relativePath: "AGENTS.md")
            guard vault.exists(url) else { return nil }
            return try vault.load(url).text
        } catch {
            Log.assistant.error("The vault's AGENTS.md could not be read: \(Log.code(error), privacy: .public)")
            return nil
        }
    }
}
