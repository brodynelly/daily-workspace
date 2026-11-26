import Combine
import DailyCore
import Foundation

// The durable Assistant's wiring: vault changes and memory as its write side, saved conversations, and routines.
// Settings → AI → Agent (`agent` in settings.json) decides what is offered; a change starts a new conversation.
extension AppModel {
    func observeAgent(startRoutines: Bool) {
        let memory = agentMemory
        assistant.setWorkspace(agentWorkspace, memoryIndex: { memory.index() })
        applyAssistantRuntime()
        assistant.onSave = { [weak self] conversation, _ in self?.conversationArchive.save(conversation) }
        conversationArchive.onDeleteAll = { [weak self] in
            guard let self, !self.assistant.isStreaming else { return }
            self.assistant.clear()
        }
        if preferences.agent.saveConversations { conversationArchive.load() }
        vaultChanges.onWrite = { [weak self] in self?.assistantContext.invalidateNotes() }
        routines.makeSession = { [weak self] origin in self?.makeRoutineSession(origin: origin) }
        // `@Published` emits before the value changes, so the sink uses the emitted settings.
        preferences.$agent
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] agent in
                guard let self else { return }
                self.applyAssistantRuntime(runtime: self.preferences.assistantRuntime, agent: agent)
            }
            .store(in: &assistantSubscriptions)
        if startRoutines { routines.start() }
    }

    /// Apply `assistantRuntime` and `agent` together, so neither drops the other's tools.
    func applyAssistantRuntime(runtime: AssistantRuntimeSettings? = nil, agent: AgentSettings? = nil) {
        assistant.applyRuntime(
            AgentRuntimeLimits(runtime ?? preferences.assistantRuntime, agent: agent ?? preferences.agent))
    }

    /// A separate session for one routine run, sharing the provider, limits, workspace and saving, so a routine
    /// never interrupts the open chat. Nil while the Assistant is off.
    func makeRoutineSession(origin: String) -> AssistantSession? {
        guard preferences.assistantEnabled else { return nil }
        return assistant.makeSibling(origin: origin)
    }

    /// Changes waiting for review, for badges.
    var pendingVaultChanges: Int { vaultChanges.pending.count }
}
