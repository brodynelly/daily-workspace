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
}

/// A failure reported to the model as `is_error: true` with a plain message.
struct ToolFailure: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Validates tool input against the tool's parameters and runs it through `AssistantContext`.
struct AssistantToolRunner: Sendable {
    let context: AssistantContext

    func run(_ use: AgentToolUse) async -> ToolRunResult {
        let arguments = use.input.map(utf8Text) ?? "{}"
        do {
            guard let tool = AssistantTool(rawValue: use.name) else {
                throw ToolFailure("There is no tool named \(use.name).")
            }
            guard let input = use.input, let object = parseJSONObject(input) else {
                throw ToolFailure("The tool input was not a valid JSON object. Call the tool again with valid input.")
            }
            let (json, citations) = try await execute(tool, ToolArguments(object, for: tool))
            let call = AssistantToolCall(
                id: use.id, name: use.name, arguments: arguments, isError: false, citations: citations)
            return ToolRunResult(call: call, block: Self.resultBlock(id: use.id, content: json, isError: false))
        } catch {
            let message: String
            if let failure = error as? ToolFailure {
                message = failure.message
            } else {
                Log.chat.error(
                    "Assistant tool \(use.name, privacy: .public) failed: \(Log.code(error), privacy: .public)")
                message =
                    (error as? LocalizedError)?.errorDescription ?? "The tool failed. The source may be unavailable."
            }
            let call = AssistantToolCall(
                id: use.id, name: use.name, arguments: arguments, isError: true, errorMessage: message, citations: [])
            return ToolRunResult(call: call, block: Self.resultBlock(id: use.id, content: message, isError: true))
        }
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
        case .searchNotes:
            let limit = args.integer("limit", default: 8, in: AssistantTool.searchLimit)
            let hits = try await Array(context.searchNotes(query: args.string("query"), limit: limit).prefix(limit))
            return try (Self.encode(["hits": hits]), hits.map { .init(kind: .path, value: $0.path) })
        case .readNote:
            let maxBytes = args.integer("max_bytes", default: 20_000, in: AssistantTool.readLimit)
            let note = try await context.readNote(path: args.string("path"), maxBytes: maxBytes).limited(to: maxBytes)
            return try (Self.encode(note), [.init(kind: .path, value: note.path)])
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

    private struct LoopsResult: Encodable {
        let rows: [ToolLoopRow]
        /// Omitted when every source was read.
        let unreadableSources: [String: String]?
    }

    private struct AgendaResult: Encodable {
        let day: String
        let events: [ToolEvent]
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return utf8Text(try encoder.encode(value))
    }
}

/// Tool input checked against the tool's parameters: no unknown keys, required keys present, types right.
struct ToolArguments {
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
