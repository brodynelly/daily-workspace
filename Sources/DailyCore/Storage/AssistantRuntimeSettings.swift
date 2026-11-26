import Foundation

/// How the Assistant's tool loop runs: limits, effort, retries, tool deadlines and result sizes, and which
/// read-only tools it is offered. Saved as `assistantRuntime` in `settings.json` and editable in
/// Settings → AI or by hand while the app is closed. Every value is clamped to a safe range, a missing or
/// mistyped key keeps its default, and unknown keys are ignored. None of these settings can add a write tool.
public struct AssistantRuntimeSettings: Codable, Equatable, Sendable {
    /// Tool rounds allowed per question before the model must answer from what it has.
    public var maxToolRounds: Int
    /// Output-token cap per model request (`max_tokens`).
    public var maxOutputTokens: Int
    /// Effort for chat turns: `low`, `medium`, `high`, `xhigh` or `max`.
    public var chatEffort: String
    /// Effort for restart-record drafts.
    public var draftEffort: String
    /// Automatic retries of a model request after a rate limit, overload, server error or dropped connection.
    public var maxRetries: Int
    /// Seconds one tool call may take before the model is told its source is unknown right now.
    public var toolTimeoutSeconds: Double
    /// Largest tool result sent to the model, in UTF-8 bytes. Longer results are cut with a note.
    public var maxToolResultBytes: Int
    /// Tool names the model is not offered, e.g. `["get_agenda"]`. Unknown names are ignored.
    public var disabledTools: [String]

    public static let defaultMaxToolRounds = 8
    public static let defaultMaxOutputTokens = 16_000
    public static let defaultMaxRetries = 2
    public static let defaultToolTimeoutSeconds: Double = 30
    /// About 25,000 tokens, Claude Code's default cap on one tool's output.
    public static let defaultMaxToolResultBytes = 100_000

    public static let toolRoundRange = 1...20
    public static let outputTokenRange = 1_024...64_000
    public static let retryRange = 0...5
    public static let toolTimeoutRange: ClosedRange<Double> = 2...300
    public static let toolResultByteRange = 4_096...400_000
    public static let efforts = ["low", "medium", "high", "xhigh", "max"]

    public init(
        maxToolRounds: Int = AssistantRuntimeSettings.defaultMaxToolRounds,
        maxOutputTokens: Int = AssistantRuntimeSettings.defaultMaxOutputTokens,
        chatEffort: String = "low",
        draftEffort: String = "medium",
        maxRetries: Int = AssistantRuntimeSettings.defaultMaxRetries,
        toolTimeoutSeconds: Double = AssistantRuntimeSettings.defaultToolTimeoutSeconds,
        maxToolResultBytes: Int = AssistantRuntimeSettings.defaultMaxToolResultBytes,
        disabledTools: [String] = []
    ) {
        self.maxToolRounds = maxToolRounds
        self.maxOutputTokens = maxOutputTokens
        self.chatEffort = chatEffort
        self.draftEffort = draftEffort
        self.maxRetries = maxRetries
        self.toolTimeoutSeconds = toolTimeoutSeconds
        self.maxToolResultBytes = maxToolResultBytes
        self.disabledTools = disabledTools
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AssistantRuntimeSettings()
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys, _ defaultValue: T) -> T {
            (try? c.decodeIfPresent(type, forKey: key)) ?? defaultValue
        }
        self.init(
            maxToolRounds: value(Int.self, .maxToolRounds, fallback.maxToolRounds),
            maxOutputTokens: value(Int.self, .maxOutputTokens, fallback.maxOutputTokens),
            chatEffort: value(String.self, .chatEffort, fallback.chatEffort),
            draftEffort: value(String.self, .draftEffort, fallback.draftEffort),
            maxRetries: value(Int.self, .maxRetries, fallback.maxRetries),
            toolTimeoutSeconds: value(Double.self, .toolTimeoutSeconds, fallback.toolTimeoutSeconds),
            maxToolResultBytes: value(Int.self, .maxToolResultBytes, fallback.maxToolResultBytes),
            disabledTools: value([String].self, .disabledTools, fallback.disabledTools))
        self = validated
    }

    /// These settings with every value in range: numbers clamped, unknown efforts reset to their default,
    /// tool names trimmed, de-duplicated and sorted.
    public var validated: AssistantRuntimeSettings {
        func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
            min(max(value, range.lowerBound), range.upperBound)
        }
        var copy = self
        copy.maxToolRounds = clamp(maxToolRounds, Self.toolRoundRange)
        copy.maxOutputTokens = clamp(maxOutputTokens, Self.outputTokenRange)
        copy.chatEffort = Self.efforts.contains(chatEffort) ? chatEffort : "low"
        copy.draftEffort = Self.efforts.contains(draftEffort) ? draftEffort : "medium"
        copy.maxRetries = clamp(maxRetries, Self.retryRange)
        copy.toolTimeoutSeconds =
            toolTimeoutSeconds.isFinite
            ? clamp(toolTimeoutSeconds, Self.toolTimeoutRange) : Self.defaultToolTimeoutSeconds
        copy.maxToolResultBytes = clamp(maxToolResultBytes, Self.toolResultByteRange)
        let names = disabledTools.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        copy.disabledTools = Array(Set(names)).sorted()
        return copy
    }
}
