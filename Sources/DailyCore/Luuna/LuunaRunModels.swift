import Foundation

/// A native run, not a ticket. Run state must never be interpreted as ticket status.
public struct LuunaRunRecord: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let projectID: String
    public let state: LuunaNativeValue
    public let revision: Int?
    public let metadata: [String: JSONValue]
    public let createdAt: String?
    public let updatedAt: String?

    /// The ticket owning a workflow run, if the runtime supplied one.
    public var ticketID: String? { metadata["ticket_id"]?.stringValue }

    private enum CodingKeys: String, CodingKey {
        case id, state, revision, metadata
        case projectID = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        projectID = try fields.decode(String.self, forKey: .projectID)
        state = try fields.decode(LuunaNativeValue.self, forKey: .state)
        revision = try fields.decodeIfPresent(Int.self, forKey: .revision)
        metadata = try fields.decodeIfPresent([String: JSONValue].self, forKey: .metadata) ?? [:]
        createdAt = try fields.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try fields.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

/// One native follow record. All fields beyond its resume sequence remain untouched.
public struct LuunaRunEvent: Decodable, Equatable, Sendable {
    public let sequence: Int
    public let fields: [String: JSONValue]

    public init(from decoder: Decoder) throws {
        let object = try [String: JSONValue](from: decoder)
        guard let sequence = object["sequence"]?.intValue, sequence >= 0 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing nonnegative event sequence"))
        }
        self.sequence = sequence
        fields = object
    }
}

/// Incremental newline-delimited follow decoder. Cursor advances only for complete, valid,
/// newly applied records; retain this instance (or its cursor) across reconnects.
public struct LuunaRunEventStream: Sendable {
    public private(set) var cursor: Int
    private var pending = Data()

    public init(after cursor: Int = 0) {
        self.cursor = cursor
    }

    /// Invalid complete lines are reported, not applied. A trailing partial line is buffered.
    public mutating func append(_ data: Data) -> (events: [LuunaRunEvent], invalidLines: [Data]) {
        pending.append(data)
        var events: [LuunaRunEvent] = []
        var invalid: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            var line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            if line.isEmpty { continue }
            do {
                let event = try JSONDecoder().decode(LuunaRunEvent.self, from: line)
                if event.sequence > cursor {
                    cursor = event.sequence
                    events.append(event)
                }
            } catch {
                invalid.append(line)
            }
        }
        return (events, invalid)
    }

    /// At end-of-stream, expose the incomplete trailing record without advancing the cursor.
    public mutating func finish() -> Data? {
        defer { pending.removeAll() }
        return pending.isEmpty ? nil : pending
    }
}
