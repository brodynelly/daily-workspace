import Foundation

/// A JSON value with a deterministic serialization: object members keep the order they were written in,
/// and `.raw` splices bytes that were frozen earlier without parsing or re-encoding them.
///
/// The Assistant builds every request body with this, so the cached prefix (tools, system) is byte-stable and
/// replayed assistant blocks (thinking signatures included) go back exactly as they were stored.
enum OrderedJSON: Sendable {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    /// Already-encoded JSON, written verbatim.
    case raw(Data)

    /// Serialize to compact UTF-8 JSON.
    func encoded() -> Data {
        var out = Data()
        write(to: &out)
        return out
    }

    private func write(to out: inout Data) {
        switch self {
        case .object(let members): Self.writeObject(members, to: &out)
        case .array(let items):
            out.append(UInt8(ascii: "["))
            for (index, item) in items.enumerated() {
                if index > 0 { out.append(UInt8(ascii: ",")) }
                item.write(to: &out)
            }
            out.append(UInt8(ascii: "]"))
        case .string(let text): Self.writeString(text, to: &out)
        case .int(let number): out.append(contentsOf: Array(String(number).utf8))
        case .double(let number):
            out.append(contentsOf: Array((number.isFinite ? String(number) : "null").utf8))
        case .bool(let flag): out.append(contentsOf: Array((flag ? "true" : "false").utf8))
        case .null: out.append(contentsOf: Array("null".utf8))
        case .raw(let data): out.append(data)
        }
    }

    private static func writeObject(_ members: [(String, OrderedJSON)], to out: inout Data) {
        out.append(UInt8(ascii: "{"))
        for (index, member) in members.enumerated() {
            if index > 0 { out.append(UInt8(ascii: ",")) }
            writeString(member.0, to: &out)
            out.append(UInt8(ascii: ":"))
            member.1.write(to: &out)
        }
        out.append(UInt8(ascii: "}"))
    }

    private static func writeString(_ text: String, to out: inout Data) {
        out.append(UInt8(ascii: "\""))
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "\""): out.append(contentsOf: [0x5C, 0x22])
            case UInt8(ascii: "\\"): out.append(contentsOf: [0x5C, 0x5C])
            case 0x0A: out.append(contentsOf: [0x5C, UInt8(ascii: "n")])
            case 0x0D: out.append(contentsOf: [0x5C, UInt8(ascii: "r")])
            case 0x09: out.append(contentsOf: [0x5C, UInt8(ascii: "t")])
            case 0x00..<0x20: out.append(contentsOf: Array(String(format: "\\u%04x", byte).utf8))
            default: out.append(byte)
            }
        }
        out.append(UInt8(ascii: "\""))
    }

    /// Convert a `JSONSerialization` result. Object keys are sorted, so the same input always encodes the same way.
    init(foundation value: Any) {
        switch value {
        case let dictionary as [String: Any]:
            self = .object(dictionary.keys.sorted().map { ($0, OrderedJSON(foundation: dictionary[$0] as Any)) })
        case let array as [Any]:
            self = .array(array.map { OrderedJSON(foundation: $0) })
        case let text as String:
            self = .string(text)
        case let number as NSNumber:
            self = Self.number(number)
        default:
            self = .null
        }
    }

    private static func number(_ number: NSNumber) -> OrderedJSON {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
        let double = number.doubleValue
        if double.rounded() == double, abs(double) < 9e15 { return .int(number.intValue) }
        return .double(double)
    }

    /// `{"type":"ephemeral"}`, the prompt-cache marker.
    static let ephemeralCache = OrderedJSON.object([("type", .string("ephemeral"))])
}

extension OrderedJSON: Equatable {
    static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool { lhs.encoded() == rhs.encoded() }
}

/// UTF-8 bytes as text; empty when they are not valid UTF-8.
func utf8Text<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
    String(bytes: bytes, encoding: .utf8) ?? ""
}

/// Parse a JSON object strictly; nil when `data` is not valid JSON or not an object.
func parseJSONObject(_ data: Data) -> [String: Any]? {
    guard !data.isEmpty else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}
