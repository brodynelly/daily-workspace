import DailyCore
import Foundation

/// One finished exchange, as the UI shows it.
struct AssistantTurn: Identifiable, Equatable, Sendable {
    let id: UUID
    let question: String
    let answer: String
    /// Every tool call of the turn, in order, with the paths and record IDs each returned.
    let toolCalls: [AssistantToolCall]
    let askedAt: Date
    /// The model that answered when a server-side fallback served the turn instead of the configured model.
    let fallbackModel: String?

    /// Everything the turn's tools returned that a claim can cite, without repeats.
    var citations: [ToolCitation] { ToolCitation.unique(toolCalls.flatMap(\.citations)) }
}

/// The Assistant's conversation: a manual tool loop over `AgentTransport` with read-only tools.
///
/// The transcript is append-only. Assistant blocks (thinking included) are stored as the raw JSON they arrived as
/// and replayed unchanged; a turn is added only when it completes, so a failed, refused or stopped turn leaves
/// the transcript exactly as it was. Nothing is persisted; the only durable output is a restart draft the user
/// accepts elsewhere.
@MainActor
final class AssistantSession: ObservableObject {
    struct Configuration: Sendable {
        var model = "claude-opus-5-5"
        var maxTokens = 16_000
        var maxToolRounds = 8
        /// `pause_turn` continuations allowed per request chain.
        var maxContinuations = 4
        var chatEffort = AgentEffort.low
        var draftEffort = AgentEffort.medium
        var now: @Sendable () -> Date = { Date() }
        var timeZone: @Sendable () -> TimeZone = { TimeZone.current }
    }

    @Published private(set) var turns: [AssistantTurn] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var error: String?
    /// The question being answered while `isStreaming`.
    @Published private(set) var pendingQuestion: String?
    /// Answer text streamed so far in the current turn.
    @Published private(set) var liveText = ""
    /// Tool calls of the current turn: running ones have no citations yet.
    @Published private(set) var liveToolCalls: [AssistantToolCall] = []

    /// The messages sent to the model, oldest first. Only ever appended to.
    private(set) var transcript: [AgentMessage] = []
    private(set) var system: [JSONValue]
    let tools = AssistantTool.definitions
    let configuration: Configuration

    let transport: AgentTransport
    let runner: AssistantToolRunner
    private let keyStore: APIKeyStore
    private var requestTask: Task<Void, Never>?
    private var draftTask: Task<RestartDraft, Error>?
    /// Bumped by `clear()` so a superseded request cannot touch state.
    private(set) var generation = 0

    static let keyService = "app.dailyworkspace.anthropic"

    init(
        transport: AgentTransport, keyStore: APIKeyStore, context: AssistantContext, vaultAgents: String? = nil,
        configuration: Configuration = Configuration()
    ) {
        self.transport = transport
        self.keyStore = keyStore
        self.runner = AssistantToolRunner(context: context)
        self.configuration = configuration
        self.system = AssistantPrompt.system(vaultAgents: vaultAgents)
    }

    /// Ask `text`. Ignored while a turn is running or when `text` is blank.
    func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !question.isEmpty else { return }
        error = nil
        guard let key = readKey() else { return }
        begin(question: question)
        let generation = generation
        let base = transcript
        let askedAt = configuration.now()
        let opening = userMessage(question)
        requestTask = Task {
            defer { if self.generation == generation { self.finish() } }
            do {
                let outcome = try await runLoop(
                    base: base, opening: opening, apiKey: key,
                    options: LoopOptions(
                        effort: configuration.chatEffort, schema: nil, generation: generation, showsProgress: true))
                guard self.generation == generation else { return }
                transcript = base + outcome.appended
                turns.append(
                    AssistantTurn(
                        id: UUID(), question: question, answer: outcome.text, toolCalls: outcome.toolCalls,
                        askedAt: askedAt, fallbackModel: fallbackModel(outcome.model)))
            } catch {
                guard self.generation == generation else { return }
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
        generation += 1
        transcript = []
        turns = []
        error = nil
        finish()
    }

    /// Start over with a new vault `AGENTS.md` (after a vault switch or when its hash changed). The system prompt
    /// is never changed under an existing conversation: that would invalidate its cache and thinking blocks.
    func startNewConversation(vaultAgents: String?) {
        clear()
        system = AssistantPrompt.system(vaultAgents: vaultAgents)
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

    private func makeDraft(slug: String, apiKey: String, generation: Int) async throws -> RestartDraft {
        let createdAt = configuration.now()
        let opening = AgentMessage(
            role: .user,
            content: [
                AssistantPrompt.contextBlock(now: createdAt, timeZone: configuration.timeZone()),
                AgentContentBlock.text(AssistantPrompt.restartRequest(project: slug)).raw,
            ])
        let outcome = try await runLoop(
            base: transcript, opening: opening, apiKey: apiKey,
            options: LoopOptions(
                effort: configuration.draftEffort, schema: AssistantPrompt.restartSchema, generation: generation,
                showsProgress: false))
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

    func userMessage(_ question: String) -> AgentMessage {
        AgentMessage(
            role: .user,
            content: [
                AssistantPrompt.contextBlock(now: configuration.now(), timeZone: configuration.timeZone()),
                AgentContentBlock.text(question).raw,
            ])
    }

    private func readKey() -> String? {
        do {
            if let key = try keyStore.read()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return key
            }
            error = "Add your Anthropic API key in Settings → AI."
        } catch {
            Log.chat.error("Keychain read failed: \(Log.code(error), privacy: .public)")
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
            Log.chat.error("Assistant turn failed: \(String(describing: agentError.kind), privacy: .public)")
            self.error = agentError.message
        } else {
            Log.chat.error("Assistant turn failed: \(Log.code(error), privacy: .public)")
            self.error = "The Assistant couldn't answer. Try again."
        }
    }

    private func fallbackModel(_ model: String?) -> String? {
        guard let model, !model.isEmpty, model != configuration.model else { return nil }
        return model
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
