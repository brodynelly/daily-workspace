import CryptoKit
import Foundation

/// A file the user read while working on a project, as it was when they read it.
public struct SourceRef: Codable, Hashable, Sendable {
    /// Vault-relative path (or another stable locator for non-vault sources).
    public var path: String
    /// Lowercase hex SHA-256 of the file's bytes when observed.
    public var sha256: String
    public var observedAt: Date

    public init(path: String, sha256: String, observedAt: Date) {
        self.path = path
        self.sha256 = sha256
        self.observedAt = observedAt
    }

    enum CodingKeys: String, CodingKey {
        case path, sha256
        case observedAt = "observed_at"
    }
}

/// A reviewed restart record: what was decided in a project session and the next exact action,
/// with the sources it was based on. Saved only after the user accepts it.
public struct RestartRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var projectSlug: String
    /// When the draft was produced.
    public var createdAt: Date
    /// When the user accepted it. A record is never written before acceptance.
    public var acceptedAt: Date
    public var decision: String
    public var nextAction: String
    public var notes: String
    public var sources: [SourceRef]

    public init(
        id: UUID = UUID(), projectSlug: String, createdAt: Date, acceptedAt: Date, decision: String,
        nextAction: String, notes: String = "", sources: [SourceRef] = []
    ) {
        self.id = id
        self.projectSlug = projectSlug
        self.createdAt = createdAt
        self.acceptedAt = acceptedAt
        self.decision = decision
        self.nextAction = nextAction
        self.notes = notes
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectSlug = "project"
        case createdAt = "created_at"
        case acceptedAt = "accepted_at"
        case decision
        case nextAction = "next_action"
        case notes, sources
    }
}

public enum RestartLedgerError: Error, Equatable, LocalizedError {
    case emptyProject

    public var errorDescription: String? {
        switch self {
        case .emptyProject: return "A restart record needs a project."
        }
    }
}

/// The records found for a project, plus the 1-based line numbers that could not be read.
/// Unreadable lines are reported, never repaired or removed.
public struct RestartLedgerRead: Equatable, Sendable {
    public var records: [RestartRecord]
    public var skippedLines: [Int]

    /// The most recently accepted record.
    public var latest: RestartRecord? { records.max { $0.acceptedAt < $1.acceptedAt } }
}

/// Append-only JSON Lines ledger of accepted restart records (`restart-ledger.jsonl`).
///
/// Every record is one line. Existing bytes are never rewritten: a corrupt or partial line stays where it is
/// and is skipped (and reported) when reading.
public struct RestartLedger: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Append `record` as one line. Creates the file (readable only by this user) if needed.
    public func append(_ record: RestartRecord) throws {
        guard !record.projectSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RestartLedgerError.emptyProject
        }
        var line = try Self.encoder.encode(record)
        line.append(0x0A)
        let files = FileManager.default
        if !files.fileExists(atPath: url.path) {
            try files.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            guard files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            // A crash mid-append can leave a partial last line. Start on a fresh line so it stays one
            // skipped line instead of corrupting this record too.
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([0x0A]) { line.insert(0x0A, at: 0) }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    /// Records for `project` in file order. A missing ledger reads as empty.
    public func records(project: String) throws -> RestartLedgerRead {
        let all = try allRecords()
        return RestartLedgerRead(
            records: all.records.filter { $0.projectSlug == project }, skippedLines: all.skippedLines)
    }

    /// Every record in file order. A missing ledger reads as empty.
    public func allRecords() throws -> RestartLedgerRead {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RestartLedgerRead(records: [], skippedLines: [])
        }
        let data = try Data(contentsOf: url)
        var records: [RestartRecord] = []
        var skipped: [Int] = []
        for (offset, line) in data.split(separator: 0x0A, omittingEmptySubsequences: false).enumerated() {
            if line.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) { continue }
            if let record = try? Self.decoder.decode(RestartRecord.self, from: Data(line)) {
                records.append(record)
            } else {
                skipped.append(offset + 1)
            }
        }
        return RestartLedgerRead(records: records, skippedLines: skipped)
    }

    /// Lowercase hex SHA-256 of `data`.
    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Lowercase hex SHA-256 of the file's bytes as they are on disk now.
    public static func sha256(ofFileAt url: URL) throws -> String {
        sha256(of: try Data(contentsOf: url, options: .mappedIfSafe))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(LedgerDate.format(date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = LedgerDate.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Not an ISO 8601 date.")
            }
            return date
        }
        return decoder
    }()
}

/// ISO 8601 with milliseconds, so a record reads back with the same instant it was written with.
private enum LedgerDate {
    // ISO8601DateFormatter is thread-safe for formatting and parsing once configured, and neither formatter is
    // mutated after initialization.
    nonisolated(unsafe) private static let precise: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func format(_ date: Date) -> String { precise.string(from: date) }

    static func parse(_ text: String) -> Date? { precise.date(from: text) ?? plain.date(from: text) }
}
