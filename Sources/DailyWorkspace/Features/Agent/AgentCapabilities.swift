import DailyCore
import Foundation

/// What the Assistant may change, from Settings → AI → Agent. It shapes the system prompt and the tool list, so
/// a change starts a new conversation.
struct AgentCapabilities: Equatable, Sendable {
    var vaultWrites = false
    var memory = false
    var approval = AgentSettings.WriteApproval.review
    var autoApplyFolders: [String] = []

    static let readOnly = AgentCapabilities()

    init() {}

    init(_ settings: AgentSettings) {
        let settings = settings.validated
        vaultWrites = settings.vaultWrites
        memory = settings.memory
        approval = settings.writeApproval
        autoApplyFolders = settings.autoApplyFolders
    }

    /// The tools these capabilities add to the read-only set.
    var tools: Set<AssistantTool> {
        var tools = Set<AssistantTool>()
        if vaultWrites { tools.formUnion(AssistantTool.vaultWrite) }
        if memory { tools.insert(.memory) }
        return tools
    }

    /// One sentence for the prompt on who approves changes.
    var approvalSentence: String {
        let links = " Anything that adds a link or embed, wikilinks included, also waits."
        switch approval {
        case .review:
            return "Every change waits for Brody's review before it reaches the vault."
        case .autoApplyFolders:
            let folders = autoApplyFolders.isEmpty ? "no folders yet" : autoApplyFolders.joined(separator: ", ")
            return "New notes and appends inside the auto-apply folders (\(folders)) apply at once; edits to "
                + "existing text and anything elsewhere wait for his review." + links
        case .autoApplyAll:
            return "New notes and appends apply at once; edits to existing text wait for his review." + links
        }
    }
}

extension AgentRuntimeLimits {
    /// Limits from `assistantRuntime`, plus the write and memory tools that `agent` allows when the app has a
    /// workspace to apply them to. `disabledTools` still removes any tool.
    init(_ settings: AssistantRuntimeSettings, agent: AgentSettings?) {
        self.init(settings)
        guard let agent else { return }
        capabilities = AgentCapabilities(agent)
        let disabled = Set(settings.validated.disabledTools)
        enabledTools.formUnion(capabilities.tools.filter { !disabled.contains($0.rawValue) })
        if !enabledTools.contains(.memory) { capabilities.memory = false }
        if enabledTools.isDisjoint(with: AssistantTool.vaultWrite) { capabilities.vaultWrites = false }
    }
}
