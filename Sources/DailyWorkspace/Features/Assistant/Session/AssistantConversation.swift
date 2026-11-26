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
