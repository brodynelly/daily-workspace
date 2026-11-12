import Foundation

/// Any JSON value. Readers keep fields they do not model in a `[String: JSONValue]` bag, so nothing an
/// owner wrote is dropped.
public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .number(let value) = self { return Int(exactly: value) }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// The array's elements when every one is a string.
    public var stringArray: [String]? {
        guard let items = arrayValue else { return nil }
        let strings = items.compactMap(\.stringValue)
        return strings.count == items.count ? strings : nil
    }

    public subscript(key: String) -> JSONValue? { objectValue?[key] }
}

/// Typed reads from a JSON object that remember which keys were used, so the rest can be preserved.
/// A key whose value has an unexpected type is not consumed and stays in `remainder`.
struct JSONFields {
    let object: [String: JSONValue]
    private(set) var consumed: Set<String> = []

    init(_ object: [String: JSONValue]) {
        self.object = object
    }

    var remainder: [String: JSONValue] { object.filter { !consumed.contains($0.key) } }

    mutating func string(_ key: String) -> String? { take(key, object[key]?.stringValue) }

    mutating func int(_ key: String) -> Int? { take(key, object[key]?.intValue) }

    mutating func strings(_ key: String) -> [String]? { take(key, object[key]?.stringArray) }

    mutating func date(_ key: String) -> Date? { take(key, JSONLines.date(object[key]?.stringValue)) }

    mutating func loopDate(_ key: String, calendar: Calendar) -> LoopDate? {
        take(key, JSONLines.loopDate(object[key]?.stringValue, calendar: calendar))
    }

    /// Marks a key as modelled even though it was read some other way.
    mutating func consume(_ key: String) { consumed.insert(key) }

    private mutating func take<T>(_ key: String, _ value: T?) -> T? {
        if value != nil { consumed.insert(key) }
        return value
    }
}

/// Tolerant JSON Lines: each non-blank line is parsed on its own, and a bad line becomes an issue
/// naming its line number instead of failing the whole file.
enum JSONLines {
    struct Row {
        let line: Int
        let object: [String: JSONValue]
    }

    static func parse(_ text: String, path: String) -> (rows: [Row], issues: [SourceIssue]) {
        let decoder = JSONDecoder()
        var rows: [Row] = []
        var issues: [SourceIssue] = []
        for (index, line) in SourceFile.lines(text).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let value = try? decoder.decode(JSONValue.self, from: Data(trimmed.utf8))
            guard let object = value?.objectValue else {
                let reason = value == nil ? "not valid JSON" : "not a JSON object"
                issues.append(SourceIssue(path: path, line: index + 1, message: "skipped line: \(reason)"))
                continue
            }
            rows.append(Row(line: index + 1, object: object))
        }
        return (rows, issues)
    }

    /// ISO 8601 with or without fractional seconds.
    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func loopDate(_ text: String?, calendar: Calendar) -> LoopDate? {
        guard let text, let instant = date(text) else { return nil }
        return LoopDate(instant: instant, raw: text, calendar: calendar)
    }
}
