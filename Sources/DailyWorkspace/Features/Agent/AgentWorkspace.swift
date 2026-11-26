import DailyCore
import Foundation

/// Where the Assistant's write tools act: vault note changes (through the approval policy and review queue) and
/// its app-owned memory. Errors reach the model as plain messages, so they never contain note text.
protocol AgentWorkspace: Sendable {
    /// Compute a change against the note on disk and apply it or queue it for review, per Settings → AI → Agent.
    func propose(_ request: VaultChangeRequest, summary: String, run: AgentRunContext) async throws
        -> VaultChangeOutcome
    /// Run one memory command and return its text result.
    func memory(_ command: AgentMemoryCommand) async throws -> String
}

/// One run of the tool loop: where its changes came from and which auto-apply budget they draw on.
struct AgentRunContext: Equatable, Sendable {
    var id = UUID()
    /// `chat` or `routine: <name>`.
    var origin: String
    var conversationID: UUID?
}

/// A vault change the model asked for.
enum VaultChangeRequest: Equatable, Sendable {
    case create(path: String, text: String)
    case edit(path: String, old: String, new: String)
    case append(path: String, text: String)

    var path: String {
        switch self {
        case .create(let path, _), .append(let path, _): return path
        case .edit(let path, _, _): return path
        }
    }
}

/// What the model is told after a write tool: applied or waiting for review, and how big the change is.
struct VaultChangeOutcome: Encodable, Equatable, Sendable {
    enum Status: String, Encodable, Sendable {
        case applied
        case awaitingReview = "awaiting_review"
    }

    let changeID: String
    let status: Status
    let path: String
    let linesAdded: Int
    let linesRemoved: Int
    /// Plain guidance for the model, e.g. why it waits for review.
    let note: String
}

/// One `memory` tool command (Anthropic's memory-tool commands).
enum AgentMemoryCommand: Equatable, Sendable {
    case view(path: String, range: ClosedRange<Int>?)
    case create(path: String, text: String)
    case replace(path: String, old: String, new: String)
    case insert(path: String, line: Int, text: String)
    case delete(path: String)
    case rename(path: String, newPath: String)

    /// Run it against `memory`, returning the text the model sees.
    func run(in memory: AgentMemory) throws -> String {
        switch self {
        case .view(let path, let range):
            return try memory.view(path, range: range)
        case .create(let path, let text):
            try memory.create(path, text: text)
            return "Saved \(path)."
        case .replace(let path, let old, let new):
            try memory.replace(path, old: old, new: new)
            return "Updated \(path)."
        case .insert(let path, let line, let text):
            try memory.insert(path, line: line, text: text)
            return "Inserted into \(path)."
        case .delete(let path):
            try memory.delete(path)
            return "Deleted \(path)."
        case .rename(let path, let newPath):
            try memory.rename(path, to: newPath)
            return "Renamed \(path) to \(newPath)."
        }
    }
}
