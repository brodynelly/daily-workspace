import DailyCore
import Foundation

/// A conversation: its turns for the UI and its transcript for the model. Saved encrypted by
/// `ConversationArchive` when the user keeps chat history on.
struct AssistantConversation: Identifiable, Sendable {
    let id: UUID
    let turns: [AssistantTurn]
    let transcript: [AgentMessage]
    let provider: AssistantProvider
    let model: String
    /// `AssistantSession.contextFingerprint` when it was built; the transcript replays only into the same one.
    let contextFingerprint: String
    let startedAt: Date
    let archivedAt: Date
    /// `chat` or `routine: <name>`.
    var origin = "chat"
    /// A question that was running when this was last saved: the app quit or crashed before it was answered.
    var interruptedQuestion: String?

    var title: String { turns.first?.question ?? interruptedQuestion ?? "Chat" }
}

struct AssistantTurn: Identifiable, Equatable, Sendable {
    let id: UUID
    let question: String
    let answer: String
    /// Final model reply only; excludes intermediate tool-use rounds, for opt-in spoken playback.
    let finalAnswer: String
    /// Every tool call of the turn, in order, with the paths and record IDs each returned.
    let toolCalls: [AssistantToolCall]
    let askedAt: Date
    /// The model that answered when a server-side fallback served the turn instead of the configured model.
    let fallbackModel: String?
    /// Tokens billed across every request of the turn.
    var usage = AgentUsage()
    /// Input tokens of the turn's last request: how full the context window is after it.
    var contextTokens = 0

    /// Tokens for the UI, for example "12,400 in (9,800 cached) · 310 out · 4,100 in context".
    var usageLine: String {
        guard contextTokens > 0 else { return usage.summary }
        let context = NumberFormatter.localizedString(from: NSNumber(value: contextTokens), number: .decimal)
        return usage.summary + " · \(context) in context"
    }

    /// Everything the turn's tools returned that a claim can cite, without repeats.
    var citations: [ToolCitation] { ToolCitation.unique(toolCalls.flatMap(\.citations)) }
}

extension AssistantSession {
    struct Configuration: Sendable {
        var provider: AssistantProvider = .anthropic
        var model = "claude-opus-5-5"
        var maxTokens = 16_000
        var maxToolRounds = 8
        /// `pause_turn` continuations allowed per request chain.
        var maxContinuations = 4
        var chatEffort = AgentEffort.low
        var draftEffort = AgentEffort.medium
        /// Automatic retries of transient model failures (rate limit, overload, server, dropped connection).
        var retry = AgentRetryPolicy()
        /// Seconds one tool call may take; nil for no deadline.
        var toolTimeout: TimeInterval? = AssistantRuntimeSettings.defaultToolTimeoutSeconds
        /// Largest tool result sent to the model, in UTF-8 bytes; nil for no cap.
        var maxToolResultBytes: Int? = AssistantRuntimeSettings.defaultMaxToolResultBytes
        /// Tools offered to the model; others are refused.
        var enabledTools: Set<AssistantTool> = Set(AssistantTool.readOnly)
        /// What the Assistant may change; shapes the system prompt.
        var capabilities = AgentCapabilities.readOnly
        /// The memory folder's file list for the start of each message, or nil without memory.
        var memoryIndex: @Sendable () -> String? = { nil }
        var now: @Sendable () -> Date = { Date() }
        var timeZone: @Sendable () -> TimeZone = { TimeZone.current }
        /// How retries wait (tests replace it).
        var sleep: @Sendable (TimeInterval) async throws -> Void = RetryingAgentTransport.taskSleep

        /// Apply runtime limits from Settings → AI / settings.json. Provider, model and clocks are unchanged.
        mutating func apply(_ limits: AgentRuntimeLimits) {
            maxToolRounds = limits.maxToolRounds
            maxTokens = limits.maxOutputTokens
            chatEffort = limits.chatEffort
            draftEffort = limits.draftEffort
            retry = limits.retry
            toolTimeout = limits.toolTimeout
            maxToolResultBytes = limits.maxToolResultBytes
            enabledTools = limits.enabledTools
            capabilities = limits.capabilities
        }
    }

    /// The current conversation, kept in memory so the Quick Panel can list it with earlier chats.
    /// Nil while a turn is running or when nothing has been asked.
    func archivedConversation(now: Date = Date()) -> AssistantConversation? {
        guard !isStreaming, !turns.isEmpty else { return nil }
        return snapshot(now: now, running: nil)
    }

    /// The conversation as it stands, with `running` marking a question still being answered.
    func snapshot(now: Date = Date(), running: String?) -> AssistantConversation {
        var conversation = AssistantConversation(
            id: conversationID, turns: turns, transcript: transcript, provider: configuration.provider,
            model: configuration.model, contextFingerprint: contextFingerprint,
            startedAt: turns.first?.askedAt ?? now, archivedAt: now)
        conversation.origin = origin
        conversation.interruptedQuestion = running
        return conversation
    }

    /// Hand the conversation to `onSave`. With no turns and nothing running it has nothing to keep, so the
    /// archive drops any file a failed first question left.
    func save(running: String?) {
        onSave?(snapshot(now: configuration.now(), running: running), running)
    }

    func userMessage(_ question: String, pageFocus: AssistantPageFocus? = nil) -> AgentMessage {
        var content = [AssistantPrompt.contextBlock(now: configuration.now(), timeZone: configuration.timeZone())]
        if configuration.capabilities.memory, let index = configuration.memoryIndex() {
            content.append(AgentContentBlock.text("<memory_index>\n\(index)\n</memory_index>").raw)
        }
        if let pageFocus { content.append(AgentContentBlock.text(pageFocus.contextText).raw) }
        content.append(AgentContentBlock.text(question).raw)
        return AgentMessage(role: .user, content: content)
    }

    /// `model` when a server-side fallback served the turn instead of the configured model.
    func fallbackModel(_ model: String?) -> String? {
        guard let model, !model.isEmpty, model != configuration.model else { return nil }
        return model
    }

    /// The restart-draft run: a separate structured request over this conversation. Nothing is written to it.
    func makeDraft(slug: String, apiKey: String, generation: Int) async throws -> RestartDraft {
        let createdAt = configuration.now()
        let opening = AgentMessage(
            role: .user,
            content: [
                AssistantPrompt.contextBlock(now: createdAt, timeZone: configuration.timeZone()),
                AgentContentBlock.text(AssistantPrompt.restartRequest(project: slug)).raw,
            ])
        let trace = AgentRunTrace(profile: "draft")
        let outcome: LoopOutcome
        do {
            outcome = try await runLoop(
                base: transcript, opening: opening, apiKey: apiKey,
                options: LoopOptions(
                    effort: configuration.draftEffort, schema: AssistantPrompt.restartSchema, generation: generation,
                    showsProgress: false, trace: trace))
            finishRun(trace, error: nil, generation: generation)
        } catch {
            finishRun(trace, error: error, generation: generation)
            throw error
        }
        let observed = (turns.flatMap(\.toolCalls) + outcome.toolCalls).flatMap(\.citations)
            .filter { $0.kind == .path }.map(\.value)
        guard
            let draft = RestartDraft(
                json: outcome.finalText, projectSlug: slug, createdAt: createdAt, observedPaths: Set(observed))
        else {
            throw AgentError(.invalidDraft, "The Assistant's draft couldn't be read. Try again.")
        }
        return draft
    }
}
