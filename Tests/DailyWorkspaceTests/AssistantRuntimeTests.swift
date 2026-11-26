import DailyCore
import XCTest

@testable import DailyWorkspace

/// Records every wait a retrying transport asks for, without waiting.
private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []

    var waits: [TimeInterval] { lock.withLock { recorded } }

    func sleep(_ seconds: TimeInterval) async throws {
        lock.withLock { recorded.append(seconds) }
    }
}

/// An `AssistantContext` whose note read never finishes in time.
private final class SlowAssistantContext: AssistantContext, @unchecked Sendable {
    func searchNotes(query: String, limit: Int) async throws -> [ToolNoteHit] { [] }

    func readNote(path: String, maxBytes: Int) async throws -> ToolNote {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return ToolNote(path: path, text: "late", truncated: false)
    }

    func openLoops(source: String?, project: String?, status: String?) async throws -> [ToolLoopRow] { [] }

    func listProjects() async -> ToolProjectInventory {
        ToolProjectInventory(state: "empty", projects: [], truncated: false, reason: nil)
    }

    func project(slug: String) async throws -> ToolProject {
        throw ToolFailure("No project \(slug).")
    }

    func agenda(day: LocalDay) async throws -> [ToolEvent] { [] }
}

private func overloaded() -> AgentError {
    AgentError.http(status: 529, errorType: nil, retryAfter: nil)
}

private func request() -> AgentRequest {
    AgentRequest(
        model: "claude-opus-5-5", maxTokens: 1_024, effort: .low, system: [], tools: [], messages: [],
        outputSchema: nil)
}

final class AgentRetryTests: XCTestCase {
    func testBackoffDoublesFromHalfASecondUpToEightSeconds() {
        let policy = AgentRetryPolicy()
        let delays = (0..<6).map { policy.delay(forRetry: $0, error: overloaded(), jitter: 0) }
        XCTAssertEqual(delays, [0.5, 1, 2, 4, 8, 8])
        XCTAssertEqual(policy.delay(forRetry: 0, error: overloaded(), jitter: 1), 0.375)
    }

    func testServerRequestedWaitWinsAndAnOverlongOneIsNotRetried() {
        let policy = AgentRetryPolicy()
        let short = AgentError.http(status: 429, errorType: nil, retryAfter: "3")
        XCTAssertEqual(policy.delay(forRetry: 0, error: short, jitter: 0.5), 3)
        let milliseconds = AgentError.http(status: 429, errorType: nil, retryAfter: "9", retryAfterMilliseconds: "250")
        XCTAssertEqual(policy.delay(forRetry: 0, error: milliseconds, jitter: 0.5), 0.25)
        let long = AgentError.http(status: 429, errorType: nil, retryAfter: "3600")
        XCTAssertNil(policy.delay(forRetry: 0, error: long, jitter: 0))
    }

    func testOnlyTransientKindsAreRetriedUnlessTheServerSaysOtherwise() {
        let policy = AgentRetryPolicy()
        XCTAssertTrue(policy.isRetryable(overloaded()))
        XCTAssertTrue(policy.isRetryable(AgentError.http(status: 500, errorType: nil, retryAfter: nil)))
        XCTAssertFalse(policy.isRetryable(AgentError.http(status: 401, errorType: nil, retryAfter: nil)))
        XCTAssertFalse(policy.isRetryable(AgentError.http(status: 400, errorType: nil, retryAfter: nil)))
        XCTAssertFalse(policy.isRetryable(AgentError(.refused, "No.")))
        XCTAssertTrue(policy.isRetryable(AgentError.http(status: 429, errorType: nil, retryAfter: "2")))
        XCTAssertFalse(
            policy.isRetryable(AgentError.http(status: 429, errorType: nil, retryAfter: nil)),
            "a 429 without retry-after is a spent cap")
        XCTAssertFalse(
            policy.isRetryable(AgentError.http(status: 529, errorType: nil, retryAfter: nil, shouldRetry: "false")))
        XCTAssertTrue(
            policy.isRetryable(AgentError.http(status: 400, errorType: nil, retryAfter: nil, shouldRetry: "true")))
    }

    func testRetryHintsDoNotChangeWhatTheUserSees() {
        let hinted = AgentError.http(status: 429, errorType: nil, retryAfter: "5")
        XCTAssertEqual(hinted.retryAfter, 5)
        XCTAssertEqual(hinted, AgentError(.rateLimited, hinted.message))
    }

    func testTransientFailureIsRetriedWithBackoffAndThenSucceeds() async throws {
        let base = FakeAgentTransport([
            .failure(overloaded()), .failure(overloaded()),
            .success(agentResponse([.text("Done.")], stop: "end_turn")),
        ])
        let sleeps = SleepLog()
        let retrying = RetryingAgentTransport(
            base: base, policy: AgentRetryPolicy(), sleep: { try await sleeps.sleep($0) }, jitter: { 0 })
        let response = try await retrying.send(request(), apiKey: "k") { _ in }

        XCTAssertEqual(response.text, "Done.")
        XCTAssertEqual(base.requests.count, 3)
        XCTAssertEqual(sleeps.waits, [0.5, 1])
    }

    func testRetriesStopAtTheLimit() async {
        let base = FakeAgentTransport([.failure(overloaded()), .failure(overloaded()), .failure(overloaded())])
        let retrying = RetryingAgentTransport(
            base: base, policy: AgentRetryPolicy(maxRetries: 1), sleep: { _ in }, jitter: { 0 })
        do {
            _ = try await retrying.send(request(), apiKey: "k") { _ in }
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual((error as? AgentError)?.kind, .overloaded)
        }
        XCTAssertEqual(base.requests.count, 2)
    }

    func testNothingIsRetriedOnceTextHasStreamed() async {
        let base = FakeAgentTransport([
            .failure(overloaded()), .success(agentResponse([.text("Again.")], stop: "end_turn")),
        ])
        base.updates = [.text("Partial ")]
        let retrying = RetryingAgentTransport(base: base, policy: AgentRetryPolicy(), sleep: { _ in }, jitter: { 0 })
        do {
            _ = try await retrying.send(request(), apiKey: "k") { _ in }
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual((error as? AgentError)?.kind, .overloaded)
        }
        XCTAssertEqual(base.requests.count, 1)
    }

    func testKeyProblemsAreNotRetried() async {
        let base = FakeAgentTransport([.failure(AgentError.http(status: 401, errorType: nil, retryAfter: nil))])
        let retrying = RetryingAgentTransport(base: base, policy: AgentRetryPolicy(), sleep: { _ in }, jitter: { 0 })
        _ = try? await retrying.send(request(), apiKey: "k") { _ in }
        XCTAssertEqual(base.requests.count, 1)
    }
}

final class AgentUsageTests: XCTestCase {
    func testStreamUsageTakesInputFromMessageStartAndCumulativeOutputFromMessageDelta() throws {
        let stream = """
            event: message_start
            data: {"type":"message_start","message":{"id":"m","model":"claude-opus-5-5","usage":{"input_tokens":40,"cache_creation_input_tokens":300,"cache_read_input_tokens":1200,"output_tokens":1}}}

            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi."}}

            event: content_block_stop
            data: {"type":"content_block_stop","index":0}

            event: message_delta
            data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":57}}

            event: message_stop
            data: {"type":"message_stop"}

            """
        var accumulator = MessageStreamAccumulator()
        for event in SSEParser.events(in: Data(stream.utf8)) { _ = try accumulator.apply(event) }
        let usage = accumulator.finalResponse().usage

        XCTAssertEqual(
            usage,
            AgentUsage(inputTokens: 40, outputTokens: 57, cacheCreationInputTokens: 300, cacheReadInputTokens: 1_200))
        XCTAssertEqual(usage.totalInputTokens, 1_540)
        XCTAssertEqual(usage.cacheHitRate, 1_200.0 / 1_540.0, accuracy: 0.0001)
    }

    func testUsageAddsUpAndSummarizes() {
        var total = AgentUsage(inputTokens: 10, outputTokens: 5)
        total += AgentUsage(inputTokens: 2, outputTokens: 1, cacheReadInputTokens: 3)
        XCTAssertEqual(total, AgentUsage(inputTokens: 12, outputTokens: 6, cacheReadInputTokens: 3))
        XCTAssertTrue(total.summary.contains("cached"))
        XCTAssertTrue(AgentUsage().isEmpty)
    }
}

final class AssistantToolLimitTests: XCTestCase {
    func testAToolThatOverrunsItsDeadlineIsReportedAsUnknownNotEmpty() async {
        let runner = AssistantToolRunner(context: SlowAssistantContext(), timeout: 0.05)
        let use = AgentToolUse(id: "t1", name: "read_note", input: Data(#"{"path":"a.md","max_bytes":100}"#.utf8))
        let clock = ContinuousClock()
        let start = clock.now
        let result = await runner.run(use)

        XCTAssertLessThan((clock.now - start).timeInterval, 2)
        XCTAssertTrue(result.timedOut)
        XCTAssertTrue(result.call.isError)
        XCTAssertTrue(result.call.errorMessage?.contains("unknown") ?? false)
        XCTAssertTrue(utf8Text(result.block).contains(#""is_error":true"#))
    }

    func testADisabledToolIsRefusedWithoutReadingAnything() async {
        let context = FakeAssistantContext()
        var enabled = Set(AssistantTool.allCases)
        enabled.remove(.searchNotes)
        let runner = AssistantToolRunner(context: context, enabledTools: enabled)
        let result = await runner.run(
            AgentToolUse(id: "t1", name: "search_notes", input: Data(#"{"query":"x","limit":3}"#.utf8)))

        XCTAssertTrue(result.call.isError)
        XCTAssertTrue(context.calls.isEmpty)
    }

    func testAnOversizedResultIsCutWithANoteAndOnlyVisibleCitations() {
        let text = String(repeating: "a", count: 500) + "01-projects/late/hub.md"
        let citations = [
            ToolCitation(kind: .path, value: "aaaa"), ToolCitation(kind: .path, value: "01-projects/late/hub.md"),
        ]
        let budgeted = AssistantToolRunner.budget(text, citations: citations, maxBytes: 300)

        XCTAssertTrue(budgeted.truncated)
        XCTAssertLessThanOrEqual(budgeted.text.utf8.count, 300)
        XCTAssertTrue(budgeted.text.contains("Result cut at 300"))
        XCTAssertEqual(budgeted.citations.map(\.value), ["aaaa"])

        let small = AssistantToolRunner.budget("short", citations: citations, maxBytes: 300)
        XCTAssertFalse(small.truncated)
        XCTAssertEqual(small.text, "short")
        XCTAssertEqual(small.citations, citations)
    }

    func testDeadlineReturnsAFastResultAndPassesErrorsThrough() async throws {
        let value = try await AgentDeadline.run(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
        do {
            _ = try await AgentDeadline.run(seconds: 5) { () async throws -> Int in throw ToolFailure("boom") }
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual(error as? ToolFailure, ToolFailure("boom"))
        }
    }

    func testCancellingTheCallerCancelsTheDeadlineRun() async {
        let task = Task {
            try await AgentDeadline.run(seconds: 30) { () async throws -> Int in
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return 1
            }
        }
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get())
    }
}

@MainActor
final class AssistantRuntimeSessionTests: XCTestCase {
    private var keys: FakeKeyStore!

    override func setUp() async throws {
        keys = FakeKeyStore()
        keys.key = "sk-ant-test"
    }

    private func makeSession(
        _ transport: FakeAgentTransport, configure: (inout AssistantSession.Configuration) -> Void = { _ in }
    ) -> AssistantSession {
        var configuration = AssistantTestClock.configuration
        configure(&configuration)
        return AssistantSession(
            transport: transport, keyStore: keys, context: FakeAssistantContext(), configuration: configuration)
    }

    private func ask(_ session: AssistantSession, _ text: String) async {
        session.send(text)
        await session.waitForCompletion()
    }

    func testRuntimeSettingsReachTheRequestAndDisabledToolsLeaveTheToolList() async throws {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Ok.")], stop: "end_turn"))])
        let session = makeSession(transport)
        session.applyRuntime(
            AgentRuntimeLimits(
                AssistantRuntimeSettings(
                    maxToolRounds: 3, maxOutputTokens: 8_000, chatEffort: "medium", disabledTools: ["get_agenda"])))
        await ask(session, "Hi")

        let body = try XCTUnwrap(transport.bodies.first)
        XCTAssertEqual(body["max_tokens"] as? Int, 8_000)
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "medium")
        let names = (body["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["get_project", "list_open_loops", "list_projects", "read_note", "search_notes"])
        XCTAssertEqual(session.configuration.maxToolRounds, 3)
    }

    func testChangingTheOfferedToolsStartsANewConversation() async {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Ok.")], stop: "end_turn"))])
        let session = makeSession(transport)
        await ask(session, "Hi")
        XCTAssertFalse(session.transcript.isEmpty)

        session.applyRuntime(AgentRuntimeLimits(AssistantRuntimeSettings(maxToolRounds: 4)))
        XCTAssertFalse(session.transcript.isEmpty, "a limit change keeps the conversation")

        session.applyRuntime(AgentRuntimeLimits(AssistantRuntimeSettings(disabledTools: ["read_note"])))
        XCTAssertTrue(session.transcript.isEmpty)
        XCTAssertTrue(session.turns.isEmpty)
    }

    func testAChatArchivedBeforeAToolChangeDoesNotReplayItsContext() async throws {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Ok.")], stop: "end_turn"))])
        let session = makeSession(transport)
        await ask(session, "Hi")
        let archived = try XCTUnwrap(session.archivedConversation())
        session.clear()

        session.applyRuntime(AgentRuntimeLimits(AssistantRuntimeSettings(disabledTools: ["read_note"])))
        XCTAssertFalse(session.restore(archived), "its tool calls were made against the old tool set")
        XCTAssertTrue(session.transcript.isEmpty)
        XCTAssertFalse(session.turns.isEmpty, "the answers stay visible")
    }

    func testATransientFailureIsRetriedInsideTheTurnAndCounted() async {
        let transport = FakeAgentTransport([
            .failure(overloaded()), .success(agentResponse([.text("Back.")], stop: "end_turn")),
        ])
        let session = makeSession(transport) { $0.retry = AgentRetryPolicy(maxRetries: 2) }
        var events: [AgentRunEvent] = []
        session.addRunObserver { events.append($0) }
        await ask(session, "Hi")

        XCTAssertNil(session.error)
        XCTAssertEqual(session.turns.map(\.answer), ["Back."])
        XCTAssertEqual(session.lastRunSummary?.retries, 1)
        XCTAssertEqual(session.lastRunSummary?.requests, 1)
        XCTAssertEqual(session.lastRunSummary?.outcome, .answered)
        XCTAssertTrue(events.contains(where: \.isRetry))
    }

    func testUsageIsSummedPerTurnAndPerConversationAndEventsCarryNoContent() async {
        var first = agentResponse(
            [toolCall("toolu_1", "search_notes", #"{"query":"alpha","limit":3}"#)], stop: "tool_use")
        first.usage = AgentUsage(inputTokens: 100, outputTokens: 20, cacheReadInputTokens: 900)
        var second = agentResponse([.text("Alpha ships the beta (01-projects/alpha/hub.md).")], stop: "end_turn")
        second.usage = AgentUsage(inputTokens: 150, outputTokens: 40, cacheReadInputTokens: 900)
        let transport = FakeAgentTransport([.success(first), .success(second)])
        let session = makeSession(transport)
        var events: [AgentRunEvent] = []
        session.addRunObserver { events.append($0) }
        await ask(session, "What about alpha?")

        let turn = session.turns.first
        XCTAssertEqual(turn?.usage, AgentUsage(inputTokens: 250, outputTokens: 60, cacheReadInputTokens: 1_800))
        XCTAssertEqual(turn?.contextTokens, 1_050)
        XCTAssertEqual(session.conversationUsage, turn?.usage)
        XCTAssertEqual(session.lastRunSummary?.toolCalls, 1)
        XCTAssertEqual(session.lastRunSummary?.toolRounds, 1)
        XCTAssertEqual(session.lastRunSummary?.requests, 2)

        let kinds = events.map { event -> String in
            switch event {
            case .requestStarted: return "request"
            case .requestFinished: return "response"
            case .retrying: return "retry"
            case .toolStarted(let name): return "tool:\(name)"
            case .toolFinished(let name, _, _, _, _): return "done:\(name)"
            case .finished: return "finished"
            }
        }
        XCTAssertEqual(
            kinds, ["request", "response", "tool:search_notes", "done:search_notes", "request", "response", "finished"])
        XCTAssertFalse(String(describing: events).contains("alpha"), "events must not carry questions or answers")

        session.clear()
        XCTAssertTrue(session.conversationUsage.isEmpty)
    }

    func testContextWindowExceededEndsTheTurnWithAClearMessage() async {
        let transport = FakeAgentTransport([
            .success(agentResponse([.text("Half")], stop: "model_context_window_exceeded"))
        ])
        let session = makeSession(transport)
        await ask(session, "Hi")

        XCTAssertTrue(session.turns.isEmpty)
        XCTAssertTrue(session.transcript.isEmpty)
        XCTAssertTrue(session.error?.contains("context window") ?? false)
        XCTAssertEqual(session.lastRunSummary?.outcome, .failed(.tooLarge))
    }
}

extension AgentRunEvent {
    fileprivate var isRetry: Bool {
        if case .retrying = self { return true }
        return false
    }
}
