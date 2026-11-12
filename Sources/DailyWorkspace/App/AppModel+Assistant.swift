import Combine
import DailyCore
import Foundation

// The Assistant's wiring: Settings → AI gates every request and picks the model, and the vault's root AGENTS.md
// (read-only) is part of the system prompt, so a new vault or a changed AGENTS.md starts a new conversation.
extension AppModel {
    /// Follow the enable switch, the model ID and the vault.
    func observeAssistant() {
        assistant.setEnabled(preferences.assistantEnabled)
        assistant.setModel(preferences.assistantModel)
        preferences.$assistantEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in self?.assistant.setEnabled(enabled) }
            .store(in: &assistantSubscriptions)
        // Typing a model ID changes it per keystroke; apply it once typing pauses.
        preferences.$assistantModel
            .dropFirst()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] model in self?.assistant.setModel(model) }
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
        assistant.startNewConversation(vaultAgents: agents)
    }

    /// The vault's root `AGENTS.md`, read through `NoteVault` and never written. Nil when absent or unreadable.
    static func readVaultAgents(root: URL) -> String? {
        let vault = NoteVault(root: root)
        do {
            let url = try vault.resolve(relativePath: "AGENTS.md")
            guard vault.exists(url) else { return nil }
            return try vault.load(url).text
        } catch {
            Log.chat.error("The vault's AGENTS.md could not be read: \(Log.code(error), privacy: .public)")
            return nil
        }
    }
}
