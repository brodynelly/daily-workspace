import DailyCore
import Foundation

/// The Assistant's write side over the app: vault changes through `VaultChanges` and memory in the app folder.
@MainActor
final class WorkspaceAgent: AgentWorkspace {
    let changes: VaultChanges
    private let memoryStore: () -> AgentMemory?
    private let settings: () -> AgentSettings

    init(changes: VaultChanges, memory: @escaping () -> AgentMemory?, settings: @escaping () -> AgentSettings) {
        self.changes = changes
        self.memoryStore = memory
        self.settings = settings
    }

    func propose(_ request: VaultChangeRequest, summary: String, run: AgentRunContext) async throws
        -> VaultChangeOutcome
    {
        do {
            return try changes.propose(request, summary: summary, run: run)
        } catch let failure as ToolFailure {
            throw failure
        } catch {
            throw ToolFailure(VaultChanges.describe(error))
        }
    }

    func memory(_ command: AgentMemoryCommand) async throws -> String {
        guard settings().memory, let memory = memoryStore() else {
            throw ToolFailure("Memory is off in Settings → AI → Agent.")
        }
        do {
            return try command.run(in: memory)
        } catch let failure as AgentMemory.Failure {
            throw ToolFailure(failure.message)
        } catch {
            throw ToolFailure("The memory folder could not be changed.")
        }
    }
}
