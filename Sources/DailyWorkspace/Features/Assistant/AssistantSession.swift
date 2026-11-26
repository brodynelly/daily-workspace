import DailyCore
import Foundation

/// The Assistant's conversation: a manual tool loop over `AgentTransport` with read-only tools.
///
/// The transcript is append-only. Assistant blocks (thinking included) are stored as the raw JSON they arrived as
/// and replayed unchanged; a turn is added only when it completes, so a failed, refused or stopped turn leaves
/// the transcript exactly as it was. `onSave` persists the conversation (encrypted, `ConversationArchive`) when a
/// question starts, so a crash leaves it marked interrupted, and again when it is answered.
@MainActor
final class AssistantSession: ObservableObject {
    @Published private(set) var turns: [AssistantTurn] = []
    /// Off until the user enables the Assistant in Settings. While off, nothing is sent: `send` and
    /// `draftRestartRecord` refuse before reading the key.
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isStreaming = false
    @Published private(set) var error: String?
    /// The question being answered while `isStreaming`.
    @Published private(set) var pendingQuestion: String?
    /// Answer text streamed so far in the current turn.
    @Published private(set) var liveText = ""
    /// Tool calls of the current turn: running ones have no citations yet.
    @Published private(set) var liveToolCalls: [AssistantToolCall] = []
    /// Tokens used by every request of this conversation, drafts included. Reset by `clear()`.
    @Published private(set) var conversationUsage = AgentUsage()
    /// What the last finished run did (counts and timings only).
    @Published private(set) var lastRunSummary: AgentRunSummary?
    /// Context the user explicitly attached (a Quick Panel harness file) for the next question only. It is sent
    /// with that question when the Assistant is enabled, then dropped; `clear()` also drops it.
    @Published var attachment: AssistantPageFocus?

    /// The messages sent to the model, oldest first. Only ever appended to.
    private(set) var transcript: [AgentMessage] = []
    private(set) var system: [JSONValue]
    /// Bumped whenever `system` or the offered tools change, so a restored conversation knows if its context
    /// still applies.
    private(set) var systemRevision = 0
    /// Definitions of the enabled tools, sorted so the cached prefix never changes within a conversation.
    var tools: [JSONValue] { AssistantTool.enabledDefinitions(configuration.enabledTools) }
    private(set) var configuration: Configuration

    let transport: AgentTransport
    let openRouterTransport: AgentTransport
    let context: AssistantContext
    /// Where write and memory tools act; nil keeps the Assistant read-only.
    var workspace: AgentWorkspace?
    /// Identifies this conversation's saved file; a new one starts with every `clear()`.
    private(set) var conversationID = UUID()
    /// `chat`, or `routine: <name>` for a routine's own session.
    var origin = "chat"
    /// Saves the conversation: called with the question when it starts (so a crash shows it interrupted) and with
    /// nil once it is answered or fails.
    var onSave: (@MainActor (AssistantConversation, String?) -> Void)?
    /// The vault's AGENTS.md and identity (vault path and hash) the system prompt was built from.
    var vaultAgents: String?
    var contextIdentity = ""
    /// Lifecycle hooks: called on the main actor for every run event. Events carry no content.
    private var runObservers: [@MainActor (AgentRunEvent) -> Void] = []
    let keyStore: APIKeyStore
    let openRouterKeyStore: APIKeyStore
    private var requestTask: Task<Void, Never>?
    private var draftTask: Task<RestartDraft, Error>?
    /// Bumped by `clear()` so a superseded request cannot touch state.
    private(set) var generation = 0

    static let keyService = "app.dailyworkspace.anthropic"
    nonisolated static let openRouterKeyService = "app.dailyworkspace.openrouter"
    static let defaultModel = Configuration().model
    static let disabledMessage = "The Assistant is off. Turn it on in Settings → AI."

    init(
        transport: AgentTransport, keyStore: APIKeyStore, context: AssistantContext, vaultAgents: String? = nil,
        configuration: Configuration = Configuration(), isEnabled: Bool = true,
        openRouterTransport: AgentTransport = OpenRouterClient(),
        openRouterKeyStore: APIKeyStore = KeychainAPIKeyStore(service: openRouterKeyService)
    ) {
        self.transport = transport
        self.openRouterTransport = openRouterTransport
        self.keyStore = keyStore
        self.openRouterKeyStore = openRouterKeyStore
        self.context = context
        self.configuration = configuration
        self.isEnabled = isEnabled
        self.vaultAgents = vaultAgents
        self.system = AssistantPrompt.system(vaultAgents: vaultAgents, capabilities: configuration.capabilities)
    }

    /// Give the write and memory tools somewhere to act. Without it they are never offered.
    func setWorkspace(_ workspace: AgentWorkspace?, memoryIndex: @escaping @Sendable () -> String? = { nil }) {
        self.workspace = workspace
        configuration.memoryIndex = memoryIndex
    }

    /// Turn sending on or off. Turning it off stops a running turn or draft.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled { stop() }
        error = nil
    }

    /// Provider and model are changed atomically. A provider switch drops the old provider's private
    /// reasoning blocks and tool-call transcript before either provider sees the next question.
    func setProvider(_ provider: AssistantProvider, model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultModel = provider == .anthropic ? Self.defaultModel : WorkspaceSettings.defaultOpenRouterModel
        let next = trimmed.isEmpty ? defaultModel : trimmed
        guard provider != configuration.provider || next != configuration.model else { return }
        configuration.provider = provider
        configuration.model = next
        if !transcript.isEmpty || isStreaming { clear() }
    }

    func setModel(_ model: String) {
        setProvider(configuration.provider, model: model)
    }

    /// Apply runtime limits. Limits take effect from the next question; a change to the offered tools starts a
    /// new conversation, because tool definitions open the cached prefix and earlier tool calls must stay valid.
    func applyRuntime(_ limits: AgentRuntimeLimits) {
        var limits = limits
        if workspace == nil {
            limits.enabledTools.subtract(AssistantTool.vaultWrite + [.memory])
            limits.capabilities = .readOnly
        }
        let capabilitiesChanged = limits.capabilities != configuration.capabilities
        let toolsChanged = limits.enabledTools != configuration.enabledTools || capabilitiesChanged
        configuration.apply(limits)
        guard toolsChanged else { return }
        if capabilitiesChanged {
            system = AssistantPrompt.system(vaultAgents: vaultAgents, capabilities: configuration.capabilities)
        }
        // Archived chats made with the old tools must not replay their tool calls against the new ones.
        systemRevision += 1
        if !transcript.isEmpty || isStreaming { clear() }
    }

    /// Register a lifecycle hook (logging, metrics, tests). It sees names, counts and timings, never content.
    func addRunObserver(_ observer: @escaping @MainActor (AgentRunEvent) -> Void) {
        runObservers.append(observer)
    }

    func emit(_ event: AgentRunEvent) {
        for observer in runObservers { observer(event) }
    }

    /// Ask `text`, optionally attaching the current page's navigation metadata only to this request.
    /// Ignored while a turn is running or when `text` is blank.
    func send(_ text: String, pageFocus: AssistantPageFocus? = nil) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !question.isEmpty else { return }
        guard isEnabled else {
            error = Self.disabledMessage
            return
        }
        error = nil
        guard let key = readKey() else { return }
        begin(question: question)
        let generation = generation
        let base = transcript
        let askedAt = configuration.now()
        let opening = userMessage(question, pageFocus: pageFocus ?? attachment)
        attachment = nil
        let run = runContext
        save(running: question)
        requestTask = Task {
            defer { if self.generation == generation { self.finish() } }
            let trace = AgentRunTrace(profile: "chat")
            let progress = LoopProgress()
            do {
                let outcome = try await runLoop(
                    base: base, opening: opening, apiKey: key,
                    options: LoopOptions(
                        effort: configuration.chatEffort, schema: nil, generation: generation, showsProgress: true,
                        trace: trace, run: run, progress: progress))
                guard self.generation == generation else { return }
                transcript = base + outcome.appended
                var turn = AssistantTurn(
                    id: UUID(), question: question, answer: outcome.text, finalAnswer: outcome.finalText,
                    toolCalls: outcome.toolCalls, askedAt: askedAt, fallbackModel: fallbackModel(outcome.model))
                turn.usage = outcome.usage
                turn.contextTokens = outcome.contextTokens
                turns.append(turn)
                finishRun(trace, error: nil, generation: generation)
                save(running: nil)
            } catch {
                finishRun(trace, error: error, generation: generation)
                guard self.generation == generation else { return }
                if progress.changedSomething, let partial = progress.outcome {
                    keepPartial(partial, question: question, base: base, askedAt: askedAt)
                }
                save(running: nil)
                report(error)
            }
        }
    }

    /// Cancel the running turn or draft. The transcript stays as it was before it.
    func stop() {
        requestTask?.cancel()
        draftTask?.cancel()
    }

    /// Start over with an empty conversation.
    func clear() {
        stop()
        attachment = nil
        generation += 1
        conversationID = UUID()
        transcript = []
        turns = []
        conversationUsage = AgentUsage()
        error = nil
        finish()
    }

    /// Show an earlier conversation again. Its transcript is replayed unchanged only for the same provider,
    /// model and system prompt; otherwise the answers stay visible and the next question starts fresh context.
    /// Returns whether the model context was restored.
    @discardableResult
    func restore(_ conversation: AssistantConversation) -> Bool {
        clear()
        conversationID = conversation.id
        turns = conversation.turns
        let sameContext =
            conversation.provider == configuration.provider && conversation.model == configuration.model
            && conversation.contextFingerprint == contextFingerprint
        transcript = sameContext ? conversation.transcript : []
        return sameContext
    }

    /// Start over with a new vault `AGENTS.md` (after a vault switch or when its hash changed). The system prompt
    /// is never changed under an existing conversation: that would invalidate its cache and thinking blocks.
    func startNewConversation(vaultAgents: String?, identity: String = "") {
        clear()
        self.vaultAgents = vaultAgents
        contextIdentity = identity
        system = AssistantPrompt.system(vaultAgents: vaultAgents, capabilities: configuration.capabilities)
        systemRevision += 1
    }

    /// Await the running turn (tests and shutdown).
    func waitForCompletion() async {
        await requestTask?.value
    }

    /// Ask for a restart record for `project`, drafted from this conversation in a separate request
    /// (structured output, medium effort). The transcript is not changed and nothing is saved: the user reviews
    /// the draft, and the caller appends it to the `RestartLedger` only after they accept.
    func draftRestartRecord(project: String) async throws -> RestartDraft {
        let slug = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming else { throw AgentError(.busy, "Wait for the current answer to finish.") }
        guard !slug.isEmpty else { throw AgentError(.invalidDraft, "Choose a project first.") }
        guard isEnabled else { throw AgentError(.disabled, Self.disabledMessage) }
        error = nil
        guard let key = readKey() else { throw AgentError(.missingKey, error ?? "") }
        begin(question: nil)
        let generation = generation
        let task = Task { try await makeDraft(slug: slug, apiKey: key, generation: generation) }
        draftTask = task
        defer { if self.generation == generation { finish() } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// The selected provider's key, or nil with `error` set. Callers send it only to that provider.
    func readKey() -> String? {
        do {
            let store = configuration.provider == .anthropic ? keyStore : openRouterKeyStore
            if let key = try store.read()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return key
            }
            error = "Add your \(configuration.provider.title) API key in Settings → AI."
        } catch {
            Log.assistant.error("Keychain read failed: \(Log.code(error), privacy: .public)")
            self.error = "The Keychain could not be read: \(error.localizedDescription)"
        }
        return nil
    }

    private func begin(question: String?) {
        isStreaming = true
        pendingQuestion = question
        liveText = ""
        liveToolCalls = []
    }

    private func finish() {
        isStreaming = false
        pendingQuestion = nil
        liveText = ""
        liveToolCalls = []
        requestTask = nil
        draftTask = nil
    }

    private func report(_ error: Error) {
        if error is CancellationError || Task.isCancelled { return }
        if let agentError = error as? AgentError {
            Log.assistant.error("Assistant turn failed: \(String(describing: agentError.kind), privacy: .public)")
            self.error = agentError.message
        } else {
            Log.assistant.error("Assistant turn failed: \(Log.code(error), privacy: .public)")
            self.error = "The Assistant couldn't answer. Try again."
        }
    }
}

// Run bookkeeping; kept in this file because it sets private state.
extension AssistantSession {
    /// A run that failed after a tool changed the vault or memory: keep its completed rounds, closed by a note,
    /// so the answer card and the model both know what already happened and a retry doesn't repeat it.
    func keepPartial(_ partial: LoopOutcome, question: String, base: [AgentMessage], askedAt: Date) {
        let note =
            "This answer stopped before it finished. The tool results above already happened; changes marked "
            + "applied are in the vault and the rest are waiting for review."
        let closing = AgentMessage(role: .assistant, content: [AgentContentBlock.text(note).raw])
        transcript = base + partial.appended + [closing]
        let answer = [partial.text, note].filter { !$0.isEmpty }.joined(separator: "\n\n")
        var turn = AssistantTurn(
            id: UUID(), question: question, answer: answer, finalAnswer: note, toolCalls: partial.toolCalls,
            askedAt: askedAt, fallbackModel: fallbackModel(partial.model))
        turn.usage = partial.usage
        turn.contextTokens = partial.contextTokens
        turns.append(turn)
    }

    /// Close a run's trace: publish and log its summary, count its tokens, and tell observers.
    func finishRun(_ trace: AgentRunTrace, error: Error?, generation: Int) {
        var summary = trace.summary
        if let agentError = error as? AgentError {
            summary.outcome = .failed(agentError.kind)
        } else if error is CancellationError || (error != nil && Task.isCancelled) {
            summary.outcome = .cancelled
        } else if error != nil {
            summary.outcome = .unknownFailure
        }
        // Counts and timings only, so the whole line can be public.
        let usage = summary.usage
        let line =
            "Assistant \(summary.profile) run \(summary.outcomeName): \(summary.requests) requests, "
            + "\(summary.toolCalls) tools, \(summary.toolErrors) tool errors, \(summary.toolTimeouts) timeouts, "
            + "\(summary.retries) retries, \(usage.totalInputTokens) in, \(usage.cacheReadInputTokens) cached, "
            + "\(usage.outputTokens) out, \(Int(summary.duration * 1000)) ms"
        Log.assistant.info("\(line, privacy: .public)")
        guard self.generation == generation else { return }
        conversationUsage += summary.usage
        lastRunSummary = summary
        emit(.finished(summary))
    }

    /// Progress from the transport, applied only while `generation` is current.
    func receive(_ update: AgentStreamUpdate, generation: Int) {
        guard self.generation == generation, isStreaming else { return }
        if case .text(let text) = update { liveText += text }
    }

    func showToolCalls(_ calls: [AssistantToolCall], generation: Int) {
        guard self.generation == generation else { return }
        liveToolCalls = calls
    }
}
