import DailyCore
import Foundation

/// A tool call as the UI shows it: what ran, with which arguments, and what it returned that can be cited.
struct AssistantToolCall: Identifiable, Equatable, Sendable {
    /// The `tool_use` ID.
    let id: String
    let name: String
    /// The arguments as JSON text, as the model sent them.
    let arguments: String
    var isError: Bool
    /// A plain message when the call failed.
    var errorMessage: String?
    /// Paths and record IDs the tool returned.
    var citations: [ToolCitation]
}

/// The outcome of one tool call: the `tool_result` block for the model and the call for the UI.
struct ToolRunResult: Sendable {
    let call: AssistantToolCall
    let block: Data
    /// True when the call ran past the runner's deadline.
    var timedOut = false
    /// True when the result was cut to the runner's size budget.
    var truncated = false
    /// How long the call took.
    var duration: TimeInterval = 0
}

/// A failure reported to the model as `is_error: true` with a plain message.
struct ToolFailure: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Validates tool input against the tool's parameters and runs it through `AssistantContext`, within the
/// runtime's limits: only enabled tools run, each call has a deadline, and each result has a size budget.
struct AssistantToolRunner: Sendable {
    let context: AssistantContext
    /// Tools the model was offered. A call to any other tool is refused without running.
    var enabledTools: Set<AssistantTool> = Set(AssistantTool.readOnly)
    /// Where vault-write and memory tools act; nil refuses them.
    var workspace: AgentWorkspace?
    /// The run the calls belong to: where changes say they came from and whose auto-apply budget they use.
    var run = AgentRunContext(origin: "chat", conversationID: nil)
    /// Seconds a call may take, or nil for no deadline.
    var timeout: TimeInterval?
    /// Largest result sent back, in UTF-8 bytes, or nil for no cap.
    var maxResultBytes: Int?

    func run(_ use: AgentToolUse) async -> ToolRunResult {
        let clock = ContinuousClock()
        let start = clock.now
        var result = await runUnmeasured(use)
        result.duration = (clock.now - start).timeInterval
        return result
    }

    private func runUnmeasured(_ use: AgentToolUse) async -> ToolRunResult {
        let arguments = use.input.map(utf8Text) ?? "{}"
        do {
            guard let tool = AssistantTool(rawValue: use.name) else {
                throw ToolFailure("There is no tool named \(use.name).")
            }
            guard enabledTools.contains(tool) else {
                throw ToolFailure("\(use.name) is turned off in Settings → AI. Answer without it, and say so.")
            }
            guard let input = use.input, let object = parseJSONObject(input) else {
                throw ToolFailure("The tool input was not a valid JSON object. Call the tool again with valid input.")
            }
            let parsed = try ToolArguments(object, for: tool)
            let output: ToolOutput
            // Writes are not raced against a deadline: an abandoned write could still land, so the model must never
            // be told its outcome is unknown. They are local and bounded by the note size cap instead.
            if let timeout, tool.isReadOnly {
                output = try await AgentDeadline.run(seconds: timeout) { [self] in
                    let (json, citations) = try await execute(tool, parsed)
                    return ToolOutput(json: json, citations: citations)
                }
            } else {
                let (json, citations) = try await execute(tool, parsed)
                output = ToolOutput(json: json, citations: citations)
            }
            let budgeted = Self.budget(output.json, citations: output.citations, maxBytes: maxResultBytes)
            let call = AssistantToolCall(
                id: use.id, name: use.name, arguments: arguments, isError: false, citations: budgeted.citations)
            return ToolRunResult(
                call: call, block: Self.resultBlock(id: use.id, content: budgeted.text, isError: false),
                truncated: budgeted.truncated)
        } catch {
            let message: String
            var timedOut = false
            if let failure = error as? ToolFailure {
                message = failure.message
            } else if let timeout = error as? ToolTimeout {
                timedOut = true
                Log.assistant.error("Assistant tool \(use.name, privacy: .public) timed out")
                message =
                    "\(use.name) didn't answer within \(Int(timeout.seconds)) seconds, so its source is unknown "
                    + "right now, not empty. Say so instead of guessing, and don't call it again for this question."
            } else if error is CancellationError {
                message = "The lookup was stopped."
            } else {
                Log.assistant.error(
                    "Assistant tool \(use.name, privacy: .public) failed: \(Log.code(error), privacy: .public)")
                message =
                    (error as? LocalizedError)?.errorDescription ?? "The tool failed. The source may be unavailable."
            }
            let call = AssistantToolCall(
                id: use.id, name: use.name, arguments: arguments, isError: true, errorMessage: message, citations: [])
            return ToolRunResult(
                call: call, block: Self.resultBlock(id: use.id, content: message, isError: true), timedOut: timedOut)
        }
    }

    /// `text` cut to `maxBytes` of UTF-8 on a character boundary, ending with a note that tells the model how to
    /// narrow the request. Only citations still visible in the kept text are returned, so nothing the model never
    /// saw counts as observed.
    static func budget(_ text: String, citations: [ToolCitation], maxBytes: Int?) -> BudgetedResult {
        guard let maxBytes, text.utf8.count > maxBytes else {
            return BudgetedResult(text: text, citations: citations, truncated: false)
        }
        let note =
            "\n[Result cut at \(maxBytes) of \(text.utf8.count) bytes. Ask for less: a smaller limit or max_bytes, "
            + "a narrower query, or one project at a time.]"
        let room = max(0, maxBytes - note.utf8.count)
        var kept = ""
        var used = 0
        for character in text {
            let size = character.utf8.count
            if used + size > room { break }
            kept.append(character)
            used += size
        }
        return BudgetedResult(
            text: kept + note, citations: citations.filter { kept.contains($0.value) }, truncated: true)
    }

    /// A tool result after the size budget: its text, the citations still visible in it, and whether it was cut.
    struct BudgetedResult {
        let text: String
        let citations: [ToolCitation]
        let truncated: Bool
    }

    static func resultBlock(id: String, content: String, isError: Bool) -> Data {
        var members: [(String, JSONValue)] = [
            ("type", .string("tool_result")), ("tool_use_id", .string(id)), ("content", .string(content)),
        ]
        if isError { members.append(("is_error", .bool(true))) }
        return JSONValue.object(members).encoded()
    }

    private func execute(_ tool: AssistantTool, _ args: ToolArguments) async throws -> (String, [ToolCitation]) {
        switch tool {
        case .createNote, .editNote, .appendToNote, .memory:
            return try await executeAgentTool(tool, args)
        case .searchNotes:
            let limit = args.integer("limit", default: 8, in: AssistantTool.searchLimit)
            let hits = try await Array(context.searchNotes(query: args.string("query"), limit: limit).prefix(limit))
            return try (Self.encode(["hits": hits]), hits.map { .init(kind: .path, value: $0.path) })
        case .readNote:
            let maxBytes = args.integer("max_bytes", default: 20_000, in: AssistantTool.readLimit)
            let note = try await context.readNote(path: args.string("path"), maxBytes: maxBytes).limited(to: maxBytes)
            return try (Self.encode(note), [.init(kind: .path, value: note.path)])
        case .listProjects:
            let inventory = await context.listProjects()
            return try (
                Self.encode(inventory),
                inventory.projects.map { ToolCitation(kind: .path, value: $0.path) }
            )
        case .listOpenLoops:
            let rows = try await context.openLoops(
                source: args.optionalString("source"), project: args.optionalString("project"),
                status: args.optionalString("status"))
            let unreadable = await context.unreadableLoopSources()
            let result = LoopsResult(rows: rows, unreadableSources: unreadable.isEmpty ? nil : unreadable)
            return try (Self.encode(result), rows.flatMap(\.citations))
        case .getProject:
            let project = try await context.project(slug: args.string("slug"))
            return try (Self.encode(project), project.citations)
        case .getAgenda:
            let text = try args.string("day")
            guard let day = Self.day(from: text) else { throw ToolFailure("day must be a date like 2026-11-12.") }
            let events = try await context.agenda(day: day)
            return try (
                Self.encode(AgendaResult(day: day.description, events: events)),
                events.map { .init(kind: .record, value: $0.id) }
            )
        }
    }

    /// Parse `YYYY-MM-DD`; nil for anything else or an impossible date.
    static func day(from text: String) -> LocalDay? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard DateComponents(year: year, month: month, day: day).isValidDate(in: calendar) else { return nil }
        return LocalDay(year: year, month: month, day: day)
    }

    /// A tool's encoded result and the citations it returned.
    private struct ToolOutput: Sendable {
        let json: String
        let citations: [ToolCitation]
    }

    private struct LoopsResult: Encodable {
        let rows: [ToolLoopRow]
        /// Omitted when every source was read.
        let unreadableSources: [String: String]?
    }

    private struct AgendaResult: Encodable {
        let day: String
        let events: [ToolEvent]
    }

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return utf8Text(try encoder.encode(value))
    }
}

/// Tool input checked against the tool's parameters: no unknown keys, required keys present, types right.
/// Immutable after the check, so it can cross into a deadline-bounded task.
struct ToolArguments: @unchecked Sendable {
    private let values: [String: Any]

    init(_ object: [String: Any], for tool: AssistantTool) throws {
        let parameters = tool.parameters
        let names = Set(parameters.map(\.name))
        if let unknown = object.keys.sorted().first(where: { !names.contains($0) }) {
            throw ToolFailure("Unknown argument \"\(unknown)\".")
        }
        for parameter in parameters {
            guard let value = object[parameter.name], !(value is NSNull) else {
                if parameter.required { throw ToolFailure("Missing required argument \"\(parameter.name)\".") }
                continue
            }
            try Self.check(value, against: parameter)
        }
        values = object
    }

    private static func check(_ value: Any, against parameter: ToolParameter) throws {
        switch parameter.type {
        case .string:
            guard let text = value as? String else { throw ToolFailure("\"\(parameter.name)\" must be a string.") }
            if let allowed = parameter.allowed, !allowed.contains(text) {
                throw ToolFailure("\"\(parameter.name)\" must be one of: \(allowed.joined(separator: ", ")).")
            }
        case .integer:
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                number.doubleValue.rounded() == number.doubleValue
            else { throw ToolFailure("\"\(parameter.name)\" must be a whole number.") }
        }
    }

    /// A required, non-blank string.
    func string(_ name: String) throws -> String {
        guard let text = optionalString(name) else { throw ToolFailure("\"\(name)\" must not be empty.") }
        return text
    }

    /// A string, or nil when absent or blank.
    func optionalString(_ name: String) -> String? {
        let text = (values[name] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// A string exactly as sent (not trimmed), or nil when absent. For note and memory text.
    func text(_ name: String) -> String? {
        values[name] as? String
    }

    /// A required string exactly as sent.
    func requiredText(_ name: String) throws -> String {
        guard let text = text(name) else { throw ToolFailure("Missing required argument \"\(name)\".") }
        return text
    }

    /// A whole number, or nil when absent.
    func optionalInteger(_ name: String) -> Int? {
        (values[name] as? NSNumber)?.intValue
    }

    /// A whole number clamped to `range`.
    func integer(_ name: String, default fallback: Int, in range: ClosedRange<Int>) -> Int {
        let number = (values[name] as? NSNumber)?.intValue ?? fallback
        return min(max(number, range.lowerBound), range.upperBound)
    }
}

extension ToolNote {
    /// At most `maxBytes` of UTF-8, cut on a character boundary.
    func limited(to maxBytes: Int) -> ToolNote {
        guard text.utf8.count > maxBytes else { return self }
        var kept = ""
        var used = 0
        for character in text {
            let size = character.utf8.count
            if used + size > maxBytes { break }
            kept.append(character)
            used += size
        }
        return ToolNote(path: path, text: kept, truncated: true)
    }
}

extension ToolLoopRow {
    var citations: [ToolCitation] {
        [ToolCitation(kind: .record, value: id)] + (path.map { [ToolCitation(kind: .path, value: $0)] } ?? [])
    }
}

extension ToolProject {
    var citations: [ToolCitation] {
        var all = [ToolCitation(kind: .path, value: hubPath)]
        all += openLoops.flatMap(\.citations)
        all += nativeTickets.map { ToolCitation(kind: .record, value: $0.id) }
        all += relatedNotes.map { ToolCitation(kind: .path, value: $0) }
        if let latestRestart { all.append(ToolCitation(kind: .record, value: latestRestart.id.uuidString)) }
        return ToolCitation.unique(all)
    }
}

extension ToolCitation {
    /// `citations` in order, without repeats.
    static func unique(_ citations: [ToolCitation]) -> [ToolCitation] {
        var seen = Set<ToolCitation>()
        return citations.filter { seen.insert($0).inserted }
    }
}
