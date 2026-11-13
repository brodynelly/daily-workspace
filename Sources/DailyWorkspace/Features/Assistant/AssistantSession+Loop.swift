import DailyCore
import Foundation

extension AssistantSession {
    /// What one run of the tool loop produced. `appended` starts with the opening user message.
    struct LoopOutcome {
        var appended: [AgentMessage]
        var toolCalls: [AssistantToolCall] = []
        var texts: [String] = []
        /// Text of the last response (the structured output, for a draft).
        var finalText = ""
        var model: String?

        var text: String { texts.filter { !$0.isEmpty }.joined(separator: "\n\n") }
    }

    /// How one run of the loop asks and reports.
    struct LoopOptions {
        var effort: AgentEffort
        /// Structured-output schema, or nil for free text.
        var schema: JSONValue?
        /// The session generation the run belongs to; progress from a stale run is dropped.
        var generation: Int
        /// Publish streamed text and tool calls (chat turns, not drafts).
        var showsProgress: Bool
    }

    /// Appended after the results of the last allowed tool round.
    static let lastRoundNote =
        "That was the last tool round allowed for this question. Answer now from what you have, and say what you "
        + "couldn't check."

    /// Send, and while the model asks for tools, run them all and send every result back in one user message.
    /// `refusal` and `max_tokens` are checked before any tool runs. Nothing is written to `transcript` here.
    func runLoop(
        base: [AgentMessage], opening: AgentMessage, apiKey: String, options: LoopOptions
    ) async throws -> LoopOutcome {
        var outcome = LoopOutcome(appended: [opening])
        var rounds = 0
        var continuations = 0
        while true {
            try Task.checkCancellation()
            let request = AgentRequest(
                model: configuration.model, maxTokens: configuration.maxTokens, effort: options.effort, system: system,
                tools: tools, messages: base + outcome.appended, outputSchema: options.schema)
            let generation = options.showsProgress ? options.generation : nil
            let selectedTransport = configuration.provider == .anthropic ? transport : openRouterTransport
            let response = try await selectedTransport.send(request, apiKey: apiKey) { [weak self] update in
                guard let generation else { return }
                await self?.receive(update, generation: generation)
            }
            try Task.checkCancellation()
            try Self.checkStop(response, provider: configuration.provider)
            outcome.appended.append(AgentMessage(role: .assistant, content: response.replayableContent.map(\.raw)))
            outcome.texts.append(response.text)
            outcome.finalText = response.text
            outcome.model = response.model
            if let generation, !response.text.isEmpty { receive(.text("\n\n"), generation: generation) }
            switch response.stopReason {
            case "tool_use" where !response.toolUses.isEmpty:
                guard rounds < configuration.maxToolRounds else {
                    throw AgentError(
                        .toolLimit,
                        "The Assistant needed more than \(configuration.maxToolRounds) rounds of lookups and stopped. "
                            + "Try a narrower question.")
                }
                rounds += 1
                let results = await runTools(response.toolUses, earlier: outcome.toolCalls, generation: generation)
                outcome.toolCalls += results.map(\.call)
                var blocks = results.map(\.block)
                if rounds == configuration.maxToolRounds {
                    blocks.append(AgentContentBlock.text(Self.lastRoundNote).raw)
                }
                outcome.appended.append(AgentMessage(role: .user, content: blocks))
            case "pause_turn":
                guard continuations < configuration.maxContinuations else {
                    throw AgentError(.incomplete, "The answer kept pausing and was stopped. Try again.")
                }
                continuations += 1
            default:
                return outcome
            }
        }
    }

    /// Refusals and truncated responses end the turn before any tool runs.
    static func checkStop(_ response: AgentResponse, provider: AssistantProvider) throws {
        switch response.stopReason {
        case "refusal":
            let category = response.stopDetails?.category ?? "none given"
            throw AgentError(
                .refused,
                "\(provider == .anthropic ? "Claude" : "The model") declined this request "
                    + "(category: \(category)). Nothing from it was kept.")
        case "max_tokens":
            throw AgentError(
                .truncated,
                "The answer reached the length limit before it finished, so it was discarded. "
                    + "Try a narrower question.")
        case _ where response.replayableContent.isEmpty:
            // An empty assistant message can't be replayed, so the turn can't be kept.
            throw AgentError(.incomplete, "The Assistant returned an empty answer. Try again.")
        default:
            return
        }
    }

    /// Run every tool call concurrently; results come back in the order the model asked for them.
    private func runTools(
        _ uses: [AgentToolUse], earlier: [AssistantToolCall], generation: Int?
    ) async -> [ToolRunResult] {
        if let generation {
            let running = uses.map {
                AssistantToolCall(
                    id: $0.id, name: $0.name, arguments: $0.input.map(utf8Text) ?? "{}",
                    isError: false, citations: [])
            }
            showToolCalls(earlier + running, generation: generation)
        }
        let runner = runner
        let results = await withTaskGroup(of: (Int, ToolRunResult).self) { group in
            for (index, use) in uses.enumerated() {
                group.addTask { (index, await runner.run(use)) }
            }
            var ordered = [ToolRunResult?](repeating: nil, count: uses.count)
            for await (index, result) in group { ordered[index] = result }
            return ordered.compactMap { $0 }
        }
        if let generation { showToolCalls(earlier + results.map(\.call), generation: generation) }
        return results
    }
}
