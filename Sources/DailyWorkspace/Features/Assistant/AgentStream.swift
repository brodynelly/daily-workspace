import Foundation

/// One content block of a model response. `raw` holds its JSON, frozen when the block completed; the transcript
/// replays exactly these bytes, so thinking signatures and tool inputs go back unchanged.
struct AgentContentBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text(String)
        case thinking(String)
        case redactedThinking
        /// `input` is the tool input JSON as received, or nil when it was not a valid JSON object.
        case toolUse(id: String, name: String, input: Data?)
        /// A server-side fallback switch point (an audit marker).
        case fallback
        case other(type: String)
    }

    let kind: Kind
    let raw: Data

    var type: String {
        switch kind {
        case .text: return "text"
        case .thinking: return "thinking"
        case .redactedThinking: return "redacted_thinking"
        case .toolUse: return "tool_use"
        case .fallback: return "fallback"
        case .other(let type): return type
        }
    }

    static func text(_ text: String) -> AgentContentBlock {
        AgentContentBlock(
            kind: .text(text), raw: JSONValue.object([("type", .string("text")), ("text", .string(text))]).encoded())
    }

    static func thinking(_ text: String, signature: String) -> AgentContentBlock {
        let raw = JSONValue.object([
            ("type", .string("thinking")), ("thinking", .string(text)), ("signature", .string(signature)),
        ])
        return AgentContentBlock(kind: .thinking(text), raw: raw.encoded())
    }

    /// A tool call. `inputJSON` is spliced verbatim when it parses as an object; otherwise `{}` is stored
    /// and the call is answered with an error instead of being run.
    static func toolUse(id: String, name: String, inputJSON: Data) -> AgentContentBlock {
        let valid = parseJSONObject(inputJSON) != nil
        let raw = JSONValue.object([
            ("type", .string("tool_use")), ("id", .string(id)), ("name", .string(name)),
            ("input", valid ? .raw(inputJSON) : .object([])),
        ])
        return AgentContentBlock(kind: .toolUse(id: id, name: name, input: valid ? inputJSON : nil), raw: raw.encoded())
    }

    /// A block that arrived complete (redacted thinking, fallback markers, unknown types), from its raw JSON.
    init?(raw: Data) {
        guard let object = parseJSONObject(raw), let type = object["type"] as? String else { return nil }
        self.raw = raw
        switch type {
        case "text": kind = .text(object["text"] as? String ?? "")
        case "thinking": kind = .thinking(object["thinking"] as? String ?? "")
        case "redacted_thinking": kind = .redactedThinking
        case "fallback": kind = .fallback
        case "tool_use":
            let input = (object["input"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            kind = .toolUse(id: object["id"] as? String ?? "", name: object["name"] as? String ?? "", input: input)
        default: kind = .other(type: type)
        }
    }

    private init(kind: Kind, raw: Data) {
        self.kind = kind
        self.raw = raw
    }
}

/// Why a refused response was refused (`stop_details`). Informational only: branch on `stopReason`.
struct AgentStopDetails: Equatable, Sendable {
    var category: String?
    var explanation: String?
}

/// A complete model response.
struct AgentResponse: Equatable, Sendable {
    var id: String?
    /// The model that produced the message (a fallback model when one served it).
    var model: String?
    var stopReason: String?
    var stopDetails: AgentStopDetails?
    var content: [AgentContentBlock]

    /// Content to keep in the transcript. After a server-side fallback, model-internal blocks from before the
    /// last switch point (thinking, redacted thinking, tool calls, unknown types) must not be echoed back.
    var replayableContent: [AgentContentBlock] {
        guard let boundary = content.lastIndex(where: { $0.kind == .fallback }) else { return content }
        return content.enumerated().compactMap { index, block in
            guard index < boundary else { return block }
            if case .text = block.kind { return block }
            return block.kind == .fallback ? block : nil
        }
    }

    /// Tool calls to run: those in the replayable content.
    var toolUses: [AgentToolUse] {
        replayableContent.compactMap { block in
            if case .toolUse(let id, let name, let input) = block.kind {
                return AgentToolUse(id: id, name: name, input: input)
            }
            return nil
        }
    }

    var text: String {
        replayableContent.compactMap { block in
            if case .text(let text) = block.kind { return text }
            return nil
        }.joined()
    }
}

/// A tool call requested by the model. `input` is nil when it was not a valid JSON object.
struct AgentToolUse: Equatable, Sendable {
    var id: String
    var name: String
    var input: Data?
}

/// Progress reported while a response streams.
enum AgentStreamUpdate: Equatable, Sendable {
    case text(String)
    case toolUse(name: String)
}

/// One server-sent event.
struct SSEEvent: Equatable, Sendable {
    var name: String?
    var data: String
}

/// Splits a byte stream into server-sent events. Blank lines end an event; comments are ignored.
struct SSEParser {
    private var lineBuffer: [UInt8] = []
    private var eventName: String?
    private var dataLines: [String] = []

    /// Feed one byte; returns an event when it completes one.
    mutating func push(_ byte: UInt8) -> SSEEvent? {
        guard byte == 0x0A else {
            lineBuffer.append(byte)
            return nil
        }
        if lineBuffer.last == 0x0D { lineBuffer.removeLast() }
        let line = utf8Text(lineBuffer)
        lineBuffer.removeAll(keepingCapacity: true)
        return feed(line: line)
    }

    /// Flush a final event that was not followed by a blank line.
    mutating func finish() -> SSEEvent? {
        if !lineBuffer.isEmpty, let event = push(0x0A) { return event }
        return feed(line: "")
    }

    private mutating func feed(line: String) -> SSEEvent? {
        if line.isEmpty {
            defer {
                eventName = nil
                dataLines = []
            }
            return dataLines.isEmpty ? nil : SSEEvent(name: eventName, data: dataLines.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let (field, value) = Self.split(line)
        switch field {
        case "event": eventName = value
        case "data": dataLines.append(value)
        default: break
        }
        return nil
    }

    private static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        var value = line[line.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        return (String(line[..<colon]), String(value))
    }

    /// Every event in `data` (tests and recorded streams).
    static func events(in data: Data) -> [SSEEvent] {
        var parser = SSEParser()
        var events = data.compactMap { parser.push($0) }
        if let last = parser.finish() { events.append(last) }
        return events
    }
}
