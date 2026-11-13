import Foundation

// These are projections returned by `lu`, not a workflow reconstructed from run history. Keep every native key
// (including keys this build does not understand) so future columns, states and detail fields remain available.
// IDs and workflow values are opaque; a completed run does not close a ticket or move its board card.

/// `lu board --project <id> --json`. Column order and card placement belong to the runtime.
public struct LuunaBoard: Codable, Equatable, Sendable {
    public let columns: [LuunaBoardLane]
    public let note: String?
    public let rawFields: [String: JSONValue]

    public init(from decoder: Decoder) throws {
        let fields = try LuunaRecordFields(from: decoder)
        columns = try fields.objects("columns").map(LuunaBoardLane.init)
        note = try fields.optionalString("note")
        rawFields = fields.values
    }

    public func encode(to encoder: Encoder) throws { try rawFields.encode(to: encoder) }

    /// Filter only by the runtime's project ID, never by a ticket title, run state or inferred status.
    public func cards(forProjectID projectID: String) -> [LuunaBoardCard] {
        columns.flatMap { $0.cards.filter { $0.projectID == projectID } }
    }
}

/// An ordered board lane, including lanes with zero cards.
public struct LuunaBoardLane: Codable, Equatable, Sendable {
    public let column: LuunaBoardColumn
    public let cards: [LuunaBoardCard]
    public let rawFields: [String: JSONValue]

    fileprivate init(_ fields: LuunaRecordFields) throws {
        column = try LuunaBoardColumn(fields.object("column"))
        cards = try fields.objects("cards").map(LuunaBoardCard.init)
        rawFields = fields.values
    }

    public init(from decoder: Decoder) throws { try self.init(LuunaRecordFields(from: decoder)) }
    public func encode(to encoder: Encoder) throws { try rawFields.encode(to: encoder) }
}

/// Workflow column ID and presentation text, all supplied by `lu board`.
public struct LuunaBoardColumn: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let description: String?
    public let rawFields: [String: JSONValue]

    fileprivate init(_ fields: LuunaRecordFields) throws {
        id = try fields.string("id")
        title = try fields.string("title")
        description = try fields.optionalString("description")
        rawFields = fields.values
    }

    public init(from decoder: Decoder) throws { try self.init(LuunaRecordFields(from: decoder)) }
    public func encode(to encoder: Encoder) throws { try rawFields.encode(to: encoder) }
}

/// Native card placement; `state` is a workflow run state, NOT the ticket's status.
public struct LuunaBoardCard: Codable, Equatable, Sendable {
    public let column: LuunaNativeValue
    public let kind: LuunaNativeValue
    public let projectID: String
    public let title: String
    public let ticketID: String?
    public let ticketRevision: Int?
    public let runID: String?
    public let state: LuunaNativeValue?
    public let planRevision: Int?
    public let rawFields: [String: JSONValue]

    fileprivate init(_ fields: LuunaRecordFields) throws {
        column = LuunaNativeValue(rawValue: try fields.string("column"))
        kind = LuunaNativeValue(rawValue: try fields.string("kind"))
        projectID = try fields.string("project_id")
        title = try fields.string("title")
        ticketID = try fields.optionalString("ticket_id")
        if kind.rawValue == "ticket" && ticketID == nil {
            throw fields.missing("ticket_id")
        }
        ticketRevision = try fields.optionalInt("ticket_revision")
        runID = try fields.optionalString("run_id")
        state = try fields.optionalString("state").map(LuunaNativeValue.init(rawValue:))
        planRevision = try fields.optionalInt("plan_revision")
        rawFields = fields.values
    }

    public init(from decoder: Decoder) throws { try self.init(LuunaRecordFields(from: decoder)) }
    public func encode(to encoder: Encoder) throws { try rawFields.encode(to: encoder) }
}

/// One element of `lu tickets <project> --json`, or `lu show-ticket <id> --json` (which adds `usage`).
/// A ticket without a run is not necessarily closed; only a native `status` key, if provided, states its status.
public struct LuunaTicketRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let projectID: String
    public let revision: Int
    public let title: String
    public let schemaVersion: String?
    public let source: LuunaNativeValue?
    public let intent: String?
    public let acceptanceCriteria: [String]?
    public let repositoryIDs: [String]?
    public let createdAt: String?
    public let updatedAt: String?
    public let status: LuunaNativeValue?
    public let usage: JSONValue?
    public let rawFields: [String: JSONValue]

    public init(from decoder: Decoder) throws {
        let fields = try LuunaRecordFields(from: decoder)
        id = try fields.string("id")
        projectID = try fields.string("project_id")
        revision = try fields.int("revision")
        title = try fields.string("title")
        schemaVersion = try fields.optionalString("schema_version")
        source = try fields.optionalString("source").map(LuunaNativeValue.init(rawValue:))
        intent = try fields.optionalString("intent")
        acceptanceCriteria = try fields.optionalStrings("acceptance_criteria")
        repositoryIDs = try fields.optionalStrings("repository_ids")
        createdAt = try fields.optionalString("created_at")
        updatedAt = try fields.optionalString("updated_at")
        status = try fields.optionalString("status").map(LuunaNativeValue.init(rawValue:))
        usage = fields.nonNull("usage")
        rawFields = fields.values
    }

    public func encode(to encoder: Encoder) throws { try rawFields.encode(to: encoder) }
}

/// `lu home --json`: runtime projects and its own blocker projection, not an app-calculated dashboard.
public struct LuunaHome: Codable, Equatable, Sendable {
    public let projects: [LuunaHomeProject]
    public let blockers: [LuunaHomeBlocker]
    public let rawFields: [String: JSONValue]

    public init(from decoder: Decoder) throws {
        let fields = try LuunaRecordFields(from: decoder)
        projects = try fields.objects("projects").map(LuunaHomeProject.init)
        blockers = try fields.objects("blockers").map(LuunaHomeBlocker.init)
        rawFields = fields.values
    }

    public func encode(to encoder: Encoder) throws { try rawFields.encode(to: encoder) }

    public func project(id: String) -> LuunaHomeProject? { projects.first { $0.id == id } }
}

public struct LuunaHomeProject: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let revision: Int?
    public let manifestHash: String?
    public let repositories: [LuunaHomeRepository]
    public let tickets: Int?
    public let activeWorkflows: Int?
    public let rawFields: [String: JSONValue]

    fileprivate init(_ fields: LuunaRecordFields) throws {
        id = try fields.string("id")
        name = try fields.string("name")
        revision = try fields.optionalInt("revision")
        manifestHash = try fields.optionalString("manifest_hash")
        repositories = try fields.objects("repositories").map(LuunaHomeRepository.init)
        tickets = try fields.optionalInt("tickets")
        activeWorkflows = try fields.optionalInt("active_workflows")
        rawFields = fields.values
    }

    public init(from decoder: Decoder) throws { try self.init(LuunaRecordFields(from: decoder)) }
    public func encode(to encoder: Encoder) throws { try rawFields.encode(to: encoder) }
}

public struct LuunaHomeRepository: Codable, Equatable, Sendable {
    public let repositoryID: String
    public let localPath: String?
    /// Baseline status belongs to the baseline, not to any ticket.
    public let baseline: JSONValue?
    public let prerequisite: JSONValue?
    public let rawFields: [String: JSONValue]

    fileprivate init(_ fields: LuunaRecordFields) throws {
        repositoryID = try fields.string("repository_id")
        localPath = try fields.optionalString("local_path")
        baseline = fields.nonNull("baseline")
        prerequisite = fields.nonNull("prerequisite")
        rawFields = fields.values
    }

    public init(from decoder: Decoder) throws { try self.init(LuunaRecordFields(from: decoder)) }
    public func encode(to encoder: Encoder) throws { try rawFields.encode(to: encoder) }
}

public struct LuunaHomeBlocker: Codable, Equatable, Sendable {
    public let kind: LuunaNativeValue
    public let projectID: String?
    public let title: String?
    public let detail: String?
    public let ticketID: String?
    public let runID: String?
    public let state: LuunaNativeValue?
    public let rawFields: [String: JSONValue]

    fileprivate init(_ fields: LuunaRecordFields) throws {
        kind = LuunaNativeValue(rawValue: try fields.string("kind"))
        projectID = try fields.optionalString("project_id")
        title = try fields.optionalString("title")
        detail = try fields.optionalString("detail")
        ticketID = try fields.optionalString("ticket_id")
        runID = try fields.optionalString("run_id")
        state = try fields.optionalString("state").map(LuunaNativeValue.init(rawValue:))
        rawFields = fields.values
    }

    public init(from decoder: Decoder) throws { try self.init(LuunaRecordFields(from: decoder)) }
    public func encode(to encoder: Encoder) throws { try rawFields.encode(to: encoder) }
}

/// Decode native objects without discarding unknown fields or silently turning malformed records into empty ones.
private struct LuunaRecordFields {
    let values: [String: JSONValue]
    let path: [CodingKey]

    init(from decoder: Decoder) throws {
        values = try [String: JSONValue](from: decoder)
        path = decoder.codingPath
    }

    private init(_ values: [String: JSONValue], path: [CodingKey]) {
        self.values = values
        self.path = path
    }

    func missing(_ key: String) -> DecodingError {
        .keyNotFound(
            LuunaRecordKey(key), .init(codingPath: path, debugDescription: "Missing required native field \(key)"))
    }

    private func required<Value>(_ key: String, as type: Value.Type, extract: (JSONValue) -> Value?) throws -> Value {
        guard let value = values[key] else { throw missing(key) }
        guard let result = extract(value) else {
            throw DecodingError.typeMismatch(
                type, .init(codingPath: path + [LuunaRecordKey(key)], debugDescription: "Invalid native field \(key)"))
        }
        return result
    }

    private func optional<Value>(_ key: String, as type: Value.Type, extract: (JSONValue) -> Value?) throws -> Value? {
        guard nonNull(key) != nil else { return nil }
        return try required(key, as: type, extract: extract)
    }

    func nonNull(_ key: String) -> JSONValue? {
        guard let value = values[key], value != .null else { return nil }
        return value
    }

    func string(_ key: String) throws -> String { try required(key, as: String.self, extract: \.stringValue) }
    func int(_ key: String) throws -> Int { try required(key, as: Int.self, extract: \.intValue) }
    func optionalString(_ key: String) throws -> String? { try optional(key, as: String.self, extract: \.stringValue) }
    func optionalInt(_ key: String) throws -> Int? { try optional(key, as: Int.self, extract: \.intValue) }
    func optionalStrings(_ key: String) throws -> [String]? {
        try optional(key, as: [String].self, extract: \.stringArray)
    }

    func object(_ key: String) throws -> LuunaRecordFields {
        let result = try required(key, as: [String: JSONValue].self, extract: \.objectValue)
        return LuunaRecordFields(result, path: path + [LuunaRecordKey(key)])
    }

    func objects(_ key: String) throws -> [LuunaRecordFields] {
        let result = try required(key, as: [JSONValue].self, extract: \.arrayValue)
        return try result.enumerated().map { index, value in
            guard let object = value.objectValue else {
                throw DecodingError.typeMismatch(
                    [String: JSONValue].self,
                    .init(
                        codingPath: path + [LuunaRecordKey(key), LuunaRecordKey(index)],
                        debugDescription: "Invalid native record"))
            }
            return LuunaRecordFields(object, path: path + [LuunaRecordKey(key), LuunaRecordKey(index)])
        }
    }
}

private struct LuunaRecordKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ key: String) {
        stringValue = key
        intValue = nil
    }
    init(_ index: Int) {
        stringValue = String(index)
        intValue = index
    }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { self.init(intValue) }
}
