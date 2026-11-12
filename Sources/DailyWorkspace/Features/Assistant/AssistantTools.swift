import DailyCore
import Foundation

/// The read-only data the Assistant's tools draw on. The app implements it over its adapters; every method
/// applies the vault exclusion policy and path containment before reading anything. Errors are shown to the
/// model as plain messages, so they must not contain note text.
protocol AssistantContext: Sendable {
    /// Lexical search over notes that are not excluded. At most `limit` hits.
    func searchNotes(query: String, limit: Int) async throws -> [ToolNoteHit]
    /// One note by vault-relative path, cut to at most `maxBytes` of UTF-8.
    func readNote(path: String, maxBytes: Int) async throws -> ToolNote
    /// Federated open-loop rows, filtered when a filter is given. Statuses are the owner's, verbatim.
    func openLoops(source: String?, project: String?, status: String?) async throws -> [ToolLoopRow]
    /// A project hub by slug, with its open loops and latest accepted restart record.
    func project(slug: String) async throws -> ToolProject
    /// Calendar events on `day`.
    func agenda(day: LocalDay) async throws -> [ToolEvent]
    /// Open-loop sources that could not be read or have not been read yet, each with why, so the model never
    /// takes a source it couldn't see for one with nothing to do.
    func unreadableLoopSources() async -> [String: String]
}

extension AssistantContext {
    func unreadableLoopSources() async -> [String: String] { [:] }
}

// Small value types local to the Assistant. The app maps its real models onto these.

struct ToolNoteHit: Codable, Equatable, Sendable {
    var path: String
    var title: String
    var snippet: String
}

struct ToolNote: Codable, Equatable, Sendable {
    var path: String
    var text: String
    /// True when the note is longer than the bytes returned.
    var truncated: Bool
}

struct ToolLoopRow: Codable, Equatable, Sendable {
    /// The record ID in its owning source (for example an Org heading ID or a Seeds issue ID).
    var id: String
    /// The owner: `local`, `org`, `seeds`, `plot` or `reminders`.
    var source: String
    var title: String
    /// The owner's status, verbatim (an Org keyword, the Seeds status, the Plot state…).
    var status: String
    var project: String?
    var path: String?
    var scheduled: String?
    var deadline: String?
    var observedAt: Date
}

struct ToolProject: Codable, Equatable, Sendable {
    var slug: String
    var title: String
    var hubPath: String
    var summary: String?
    var decisions: [String]
    var checkouts: [String]
    var openLoops: [ToolLoopRow]
    var relatedNotes: [String]
    var latestRestart: RestartRecord?
}

struct ToolEvent: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendar: String
    var location: String?
}

/// Something a tool returned that a claim can cite: a vault path or a source record ID.
struct ToolCitation: Hashable, Sendable {
    enum Kind: String, Sendable {
        case path, record
    }

    let kind: Kind
    let value: String
}

/// One input parameter of a tool. The JSON schema and the input check are both built from these.
struct ToolParameter: Sendable {
    enum ValueType: String, Sendable {
        case string, integer
    }

    let name: String
    let type: ValueType
    let description: String
    var required = true
    var allowed: [String]?

    var schema: JSONValue {
        var members: [(String, JSONValue)] = [("type", .string(type.rawValue))]
        if let allowed { members.append(("enum", .array(allowed.map { .string($0) }))) }
        members.append(("description", .string(description)))
        return .object(members)
    }
}

/// The Assistant's tools. All are read-only.
enum AssistantTool: String, CaseIterable, Sendable {
    case getAgenda = "get_agenda"
    case getProject = "get_project"
    case listOpenLoops = "list_open_loops"
    case readNote = "read_note"
    case searchNotes = "search_notes"

    static let sources = ["local", "org", "plot", "reminders", "seeds"]
    static let searchLimit = 1...25
    static let readLimit = 1...100_000

    /// Definitions sorted by name, rendered the same way every time so the cached prefix never changes.
    static let definitions: [JSONValue] = allCases.sorted { $0.rawValue < $1.rawValue }.map(\.definition)

    var definition: JSONValue {
        let properties = parameters.sorted { $0.name < $1.name }.map { ($0.name, $0.schema) }
        let required = parameters.filter(\.required).map(\.name).sorted()
        return .object([
            ("name", .string(rawValue)),
            ("description", .string(summary)),
            ("strict", .bool(true)),
            (
                "input_schema",
                .object([
                    ("type", .string("object")),
                    ("properties", .object(properties)),
                    ("required", .array(required.map { .string($0) })),
                    ("additionalProperties", .bool(false)),
                ])
            ),
        ])
    }

    var summary: String {
        switch self {
        case .searchNotes:
            return "Search the vault's notes by words. Call this first when a question involves notes, projects or "
                + "past decisions and you don't have a path yet. Returns paths and short snippets."
        case .readNote:
            return "Read one note by its vault-relative path (from search_notes, get_project or the user). Call this "
                + "before quoting or summarizing a note. Excluded paths are refused."
        case .listOpenLoops:
            return "List open loops (tasks, issues, reminders) across their owners, with each owner's status "
                + "verbatim and a record ID to cite. Call this for any question about what is open, due or done."
        case .getProject:
            return "Get a project by slug: hub summary, decisions, checkouts, its open loops and the latest "
                + "accepted restart record. Call this when the user asks to resume or review a project."
        case .getAgenda:
            return "Get the calendar events for one day. Call this for questions about meetings or the schedule."
        }
    }

    var parameters: [ToolParameter] {
        switch self {
        case .searchNotes:
            return [
                ToolParameter(name: "query", type: .string, description: "Words to search for."),
                ToolParameter(name: "limit", type: .integer, description: "Maximum hits, 1 to 25. Use 8 if unsure."),
            ]
        case .readNote:
            return [
                ToolParameter(
                    name: "path", type: .string, description: "Vault-relative path, e.g. 01-projects/x/hub.md."),
                ToolParameter(
                    name: "max_bytes", type: .integer,
                    description: "Most bytes to return, 1 to 100000. Use 20000 if unsure."),
            ]
        case .listOpenLoops:
            return [
                ToolParameter(
                    name: "source", type: .string, description: "Only rows from this owner.", required: false,
                    allowed: Self.sources),
                ToolParameter(
                    name: "project", type: .string, description: "Only rows for this project slug.", required: false),
                ToolParameter(
                    name: "status", type: .string, description: "Only rows with this native status, e.g. TODO.",
                    required: false),
            ]
        case .getProject:
            return [ToolParameter(name: "slug", type: .string, description: "Project slug, e.g. daily-workspace.")]
        case .getAgenda:
            return [ToolParameter(name: "day", type: .string, description: "The day as YYYY-MM-DD.")]
        }
    }
}
