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
        /// Tokens billed across every request of the run.
        var usage = AgentUsage()
        /// Input tokens of the last request: how much of the context window the conversation now fills.
        var contextTokens = 0

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
        /// Collects the run's content-free summary.
        var trace: AgentRunTrace?
        /// Where the run's vault changes say they came from.
        var run = AgentRunContext(origin: "chat", conversationID: nil)
        /// Holds what the run completed so far, for a run that fails after a tool changed something.
        var progress: LoopProgress?
        /// Run only read-only tools. The tool definitions stay the same, so the cached prefix and the conversation
        /// stay valid, but a write or memory call is refused rather than run.
        var readOnly = false
    }

    /// The loop's outcome up to its last complete tool round.
    @MainActor
    final class LoopProgress {
        var outcome: LoopOutcome?

        /// True when a completed tool call may have changed the vault or memory.
        var changedSomething: Bool {
            outcome?.toolCalls.contains { call in
                !call.isError && AssistantTool(rawValue: call.name).map { !$0.isReadOnly } == true
            } ?? false
        }
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
        // One snapshot per run: a Settings change mid-answer applies from the next question, never mid-run.
        let configuration = self.configuration
        let tools = AssistantTool.enabledDefinitions(configuration.enabledTools)
        var runnerConfiguration = configuration
        if options.readOnly { runnerConfiguration.enabledTools.formIntersection(AssistantTool.readOnly) }
        let runner = makeRunner(runnerConfiguration, run: options.run)
        var outcome = LoopOutcome(appended: [opening])
        var rounds = 0
        var continuations = 0
        while true {
            try Task.checkCancellation()
            let request = AgentRequest(
                model: configuration.model, maxTokens: configuration.maxTokens, effort: options.effort, system: system,
                tools: tools, messages: base + outcome.appended, outputSchema: options.schema)
            let generation = options.showsProgress ? options.generation : nil
            let response = try await sendRequest(
                request, configuration: configuration, apiKey: apiKey, generation: generation, trace: options.trace)
            outcome.usage += response.usage
            outcome.contextTokens = response.usage.totalInputTokens
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
                options.trace?.noteToolRound()
                let results = await runTools(
                    response.toolUses, runner: runner, earlier: outcome.toolCalls, generation: generation,
                    trace: options.trace)
                outcome.toolCalls += results.map(\.call)
                var blocks = results.map(\.block)
                if rounds == configuration.maxToolRounds {
                    blocks.append(AgentContentBlock.text(Self.lastRoundNote).raw)
                }
                outcome.appended.append(AgentMessage(role: .user, content: blocks))
                options.progress?.outcome = outcome
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

    /// One model request through the selected provider, with retries, reported to the trace and observers.
    private func sendRequest(
        _ request: AgentRequest, configuration: Configuration, apiKey: String, generation: Int?,
        trace: AgentRunTrace?
    ) async throws -> AgentResponse {
        let number = (trace?.summary.requests ?? 0) + 1
        record(.requestStarted(request: number), trace: trace)
        let selected = configuration.provider == .anthropic ? transport : openRouterTransport
        let retrying = RetryingAgentTransport(
            base: selected, policy: configuration.retry, sleep: configuration.sleep,
            onRetry: { [weak self] event in await self?.record(.retrying(event), trace: trace) })
        let clock = ContinuousClock()
        let start = clock.now
        let response = try await retrying.send(request, apiKey: apiKey) { [weak self] update in
            guard let generation else { return }
            await self?.receive(update, generation: generation)
        }
        record(
            .requestFinished(
                request: number, stopReason: response.stopReason, model: response.model, usage: response.usage,
                duration: (clock.now - start).timeInterval),
            trace: trace)
        return response
    }

    func record(_ event: AgentRunEvent, trace: AgentRunTrace?) {
        trace?.record(event)
        emit(event)
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
        case "model_context_window_exceeded":
            throw AgentError(
                .tooLarge,
                "This chat has grown past the model's context window, so the answer was discarded. "
                    + "Start a new chat and ask again.")
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
        _ uses: [AgentToolUse], runner: AssistantToolRunner, earlier: [AssistantToolCall], generation: Int?,
        trace: AgentRunTrace?
    ) async -> [ToolRunResult] {
        for use in uses { record(.toolStarted(name: use.name), trace: trace) }
        if let generation {
            let running = uses.map {
                AssistantToolCall(
                    id: $0.id, name: $0.name, arguments: $0.input.map(utf8Text) ?? "{}",
                    isError: false, citations: [])
            }
            showToolCalls(earlier + running, generation: generation)
        }
        let results = await withTaskGroup(of: (Int, ToolRunResult).self) { group in
            for (index, use) in uses.enumerated() {
                group.addTask { (index, await runner.run(use)) }
            }
            var ordered = [ToolRunResult?](repeating: nil, count: uses.count)
            for await (index, result) in group { ordered[index] = result }
            return ordered.compactMap { $0 }
        }
        for result in results {
            record(
                .toolFinished(
                    name: result.call.name, isError: result.call.isError, timedOut: result.timedOut,
                    truncated: result.truncated, duration: result.duration),
                trace: trace)
        }
        if let generation { showToolCalls(earlier + results.map(\.call), generation: generation) }
        return results
    }
}
