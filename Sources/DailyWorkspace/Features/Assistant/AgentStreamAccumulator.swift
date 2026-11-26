import Foundation

/// Builds an `AgentResponse` from Messages API stream events: text and thinking deltas, signatures, and tool
/// input assembled from `input_json_delta` fragments.
struct MessageStreamAccumulator {
    private var response = AgentResponse(content: [])
    private var open: [Int: PartialBlock] = [:]
    private var closed: [Int: AgentContentBlock] = [:]
    /// True once `message_stop` arrived.
    private(set) var isComplete = false

    private struct PartialBlock {
        var type: String
        /// The `content_block` of `content_block_start`, kept for blocks that arrive complete.
        var start: Data
        var id = ""
        var name = ""
        var text = ""
        var signature = ""
        var inputJSON = ""
    }

    /// Apply one event and return progress worth showing, if any. A stream `error` event throws.
    mutating func apply(_ event: SSEEvent) throws -> AgentStreamUpdate? {
        guard let object = parseJSONObject(Data(event.data.utf8)) else { return nil }
        switch object["type"] as? String ?? event.name {
        case "message_start":
            let message = object["message"] as? [String: Any]
            response.id = message?["id"] as? String
            response.model = message?["model"] as? String
            response.usage.merge(message?["usage"] as? [String: Any])
        case "content_block_start": return startBlock(object)
        case "content_block_delta": return applyDelta(object)
        case "content_block_stop":
            if let index = object["index"] as? Int { close(index) }
        case "message_delta": applyMessageDelta(object)
        case "message_stop": isComplete = true
        case "error": throw AgentError.stream(object["error"] as? [String: Any])
        default: break  // ping and event types this client does not use
        }
        return nil
    }

    /// The response so far. Blocks still open are closed with what has arrived.
    func finalResponse() -> AgentResponse {
        var copy = self
        for index in copy.open.keys { copy.close(index) }
        copy.response.content = copy.closed.keys.sorted().compactMap { copy.closed[$0] }
        return copy.response
    }

    private mutating func startBlock(_ object: [String: Any]) -> AgentStreamUpdate? {
        guard let index = object["index"] as? Int, let block = object["content_block"] as? [String: Any],
            let type = block["type"] as? String
        else { return nil }
        var partial = PartialBlock(type: type, start: JSONValue(foundation: block).encoded())
        partial.id = block["id"] as? String ?? ""
        partial.name = block["name"] as? String ?? ""
        partial.text = (block["text"] as? String) ?? (block["thinking"] as? String) ?? ""
        partial.signature = block["signature"] as? String ?? ""
        open[index] = partial
        if type == "tool_use" { return .toolUse(name: partial.name) }
        if type == "text", !partial.text.isEmpty { return .text(partial.text) }
        return nil
    }

    private mutating func applyDelta(_ object: [String: Any]) -> AgentStreamUpdate? {
        guard let index = object["index"] as? Int, let delta = object["delta"] as? [String: Any],
            open[index] != nil
        else { return nil }
        switch delta["type"] as? String {
        case "text_delta":
            let text = delta["text"] as? String ?? ""
            open[index]?.text += text
            return text.isEmpty ? nil : .text(text)
        case "thinking_delta": open[index]?.text += delta["thinking"] as? String ?? ""
        case "signature_delta": open[index]?.signature += delta["signature"] as? String ?? ""
        case "input_json_delta": open[index]?.inputJSON += delta["partial_json"] as? String ?? ""
        default: break
        }
        return nil
    }

    private mutating func applyMessageDelta(_ object: [String: Any]) {
        let delta = object["delta"] as? [String: Any]
        response.usage.merge(object["usage"] as? [String: Any])
        if let reason = delta?["stop_reason"] as? String { response.stopReason = reason }
        let details = (delta?["stop_details"] ?? object["stop_details"]) as? [String: Any]
        if let details {
            response.stopDetails = AgentStopDetails(
                category: details["category"] as? String, explanation: details["explanation"] as? String)
        }
    }

    private mutating func close(_ index: Int) {
        guard let partial = open.removeValue(forKey: index) else { return }
        switch partial.type {
        case "text": closed[index] = .text(partial.text)
        case "thinking": closed[index] = .thinking(partial.text, signature: partial.signature)
        case "tool_use":
            let input = partial.inputJSON.isEmpty ? Data("{}".utf8) : Data(partial.inputJSON.utf8)
            closed[index] = .toolUse(id: partial.id, name: partial.name, inputJSON: input)
        default:
            closed[index] = AgentContentBlock(raw: partial.start)
        }
    }
}
