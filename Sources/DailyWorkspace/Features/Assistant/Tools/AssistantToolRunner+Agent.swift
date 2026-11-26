import DailyCore
import Foundation

extension AssistantToolRunner {
    /// The vault write and memory tools, through `workspace`. Results say exactly what happened: applied, or
    /// waiting for Brody's review, never "saved" for a change that is only queued.
    func executeAgentTool(_ tool: AssistantTool, _ args: ToolArguments) async throws -> (String, [ToolCitation]) {
        guard let workspace else {
            throw ToolFailure(
                "\(tool.rawValue) is turned off in Settings → AI → Agent. Answer without it, and say so.")
        }
        switch tool {
        case .createNote:
            let request = VaultChangeRequest.create(path: try args.string("path"), text: try args.requiredText("text"))
            return try await propose(request, summary: args.optionalString("summary"), in: workspace)
        case .editNote:
            let request = VaultChangeRequest.edit(
                path: try args.string("path"), old: try args.requiredText("old_text"),
                new: try args.requiredText("new_text"))
            return try await propose(request, summary: args.optionalString("summary"), in: workspace)
        case .appendToNote:
            let request = VaultChangeRequest.append(path: try args.string("path"), text: try args.requiredText("text"))
            return try await propose(request, summary: args.optionalString("summary"), in: workspace)
        case .memory:
            let command = try Self.memoryCommand(args)
            let text = try await workspace.memory(command)
            return (text, [])
        default:
            throw ToolFailure("There is no tool named \(tool.rawValue).")
        }
    }

    private func propose(
        _ request: VaultChangeRequest, summary: String?, in workspace: AgentWorkspace
    ) async throws -> (String, [ToolCitation]) {
        let outcome = try await workspace.propose(request, summary: summary ?? "", run: run)
        return try (Self.encode(outcome), [ToolCitation(kind: .path, value: outcome.path)])
    }

    static func memoryCommand(_ args: ToolArguments) throws -> AgentMemoryCommand {
        let path = try args.string("path")
        switch try args.string("command") {
        case "view":
            let start = args.optionalInteger("view_start")
            let end = args.optionalInteger("view_end")
            let range = start.map { first in first...max(first, end ?? Int.max) }
            return .view(path: path, range: range)
        case "create":
            return .create(path: path, text: try args.requiredText("file_text"))
        case "str_replace":
            return .replace(path: path, old: try args.requiredText("old_str"), new: args.text("new_str") ?? "")
        case "insert":
            guard let line = args.optionalInteger("insert_line") else {
                throw ToolFailure("insert needs insert_line.")
            }
            return .insert(path: path, line: line, text: try args.requiredText("insert_text"))
        case "delete":
            return .delete(path: path)
        case "rename":
            return .rename(path: path, newPath: try args.string("new_path"))
        default:
            throw ToolFailure("command must be one of: \(AssistantTool.memoryCommands.joined(separator: ", ")).")
        }
    }
}
