import Foundation

/// Token counts the Messages API reports for one response (`usage`), or a sum of them across a turn.
/// Counts only: never any text. Dollar cost is left to the provider's console, since prices change.
struct AgentUsage: Equatable, Sendable {
    /// Input tokens after the last cache breakpoint (not read from or written to the cache).
    var inputTokens = 0
    var outputTokens = 0
    /// Input tokens written to the prompt cache by this request.
    var cacheCreationInputTokens = 0
    /// Input tokens read from the prompt cache.
    var cacheReadInputTokens = 0

    /// Every input token the request carried, cached or not.
    var totalInputTokens: Int { inputTokens + cacheCreationInputTokens + cacheReadInputTokens }

    var isEmpty: Bool { totalInputTokens == 0 && outputTokens == 0 }

    /// Share of input tokens served from the cache, 0 to 1.
    var cacheHitRate: Double {
        totalInputTokens == 0 ? 0 : Double(cacheReadInputTokens) / Double(totalInputTokens)
    }

    /// Replace each count present in a `usage` object. `message_start` carries the input counts and
    /// `message_delta` carries cumulative counts, so later values win.
    mutating func merge(_ object: [String: Any]?) {
        guard let object else { return }
        if let value = Self.count(object["input_tokens"]) { inputTokens = value }
        if let value = Self.count(object["output_tokens"]) { outputTokens = value }
        if let value = Self.count(object["cache_creation_input_tokens"]) { cacheCreationInputTokens = value }
        if let value = Self.count(object["cache_read_input_tokens"]) { cacheReadInputTokens = value }
    }

    static func + (lhs: AgentUsage, rhs: AgentUsage) -> AgentUsage {
        AgentUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens, outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheCreationInputTokens: lhs.cacheCreationInputTokens + rhs.cacheCreationInputTokens,
            cacheReadInputTokens: lhs.cacheReadInputTokens + rhs.cacheReadInputTokens)
    }

    static func += (lhs: inout AgentUsage, rhs: AgentUsage) {
        lhs = lhs + rhs
    }

    /// A short line for the UI, for example "12,400 in (9,800 cached) · 310 out".
    var summary: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        func format(_ value: Int) -> String { formatter.string(from: NSNumber(value: value)) ?? String(value) }
        var text = "\(format(totalInputTokens)) in"
        if cacheReadInputTokens > 0 { text += " (\(format(cacheReadInputTokens)) cached)" }
        return text + " · \(format(outputTokens)) out"
    }

    private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return max(0, number.intValue)
    }
}
