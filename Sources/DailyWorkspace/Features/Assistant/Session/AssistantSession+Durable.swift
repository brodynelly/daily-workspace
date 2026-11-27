import DailyCore
import Foundation

// Runs, workspace and persistence identity for the durable Assistant.
extension AssistantSession {
    /// The tool runner with the current limits.
    var runner: AssistantToolRunner { makeRunner(configuration, run: runContext) }

    func makeRunner(_ configuration: Configuration, run: AgentRunContext) -> AssistantToolRunner {
        AssistantToolRunner(
            context: context, enabledTools: configuration.enabledTools, workspace: workspace, run: run,
            timeout: configuration.toolTimeout, maxResultBytes: configuration.maxToolResultBytes)
    }

    /// A fresh run of this conversation.
    var runContext: AgentRunContext { AgentRunContext(origin: origin, conversationID: conversationID) }

    /// A new, empty session with this one's transports, keys, context, limits, prompt and workspace, for a routine
    /// run that must not disturb this conversation. It saves through the same `onSave`.
    func makeSibling(origin: String) -> AssistantSession {
        let sibling = AssistantSession(
            transport: transport, keyStore: keyStore, context: context, vaultAgents: vaultAgents,
            configuration: configuration, isEnabled: isEnabled, openRouterTransport: openRouterTransport,
            openRouterKeyStore: openRouterKeyStore)
        sibling.workspace = workspace
        sibling.contextIdentity = contextIdentity
        sibling.origin = origin
        sibling.onSave = onSave
        return sibling
    }

    /// Identifies the model context a transcript was built in: the vault identity, system prompt and tools. A
    /// saved conversation is replayed only into the same context, across launches too.
    var contextFingerprint: String {
        let bytes =
            Data(contextIdentity.utf8) + OrderedJSON.array(system).encoded() + OrderedJSON.array(tools).encoded()
        return RestartLedger.sha256(of: bytes)
    }
}
