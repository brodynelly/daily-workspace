import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class AssistantSessionTests: XCTestCase {
    private var keys: FakeKeyStore!
    private var context: FakeAssistantContext!

    override func setUp() async throws {
        keys = FakeKeyStore()
        keys.key = "sk-ant-test"
        context = FakeAssistantContext()
    }

    private func makeSession(_ transport: FakeAgentTransport, vaultAgents: String? = nil) -> AssistantSession {
        AssistantSession(
            transport: transport, keyStore: keys, context: context, vaultAgents: vaultAgents,
            configuration: AssistantTestClock.configuration)
    }

    private func ask(_ session: AssistantSession, _ text: String) async {
        session.send(text)
        await session.waitForCompletion()
    }

    func testRequestIsAdaptiveLowEffortStrictSortedCachedAndKeepsTheDateOutOfTheSystemPrompt() async throws {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Nothing due.")], stop: "end_turn"))])
        let session = makeSession(transport, vaultAgents: "# Vault rules\nNever write to the root.")
        await ask(session, "What's due today?")

        let body = try XCTUnwrap(transport.bodies.first)
        for banned in ["temperature", "top_p", "top_k"] { XCTAssertNil(body[banned], banned) }
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 16_000)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "adaptive")
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual((body["tool_choice"] as? [String: Any])?["type"] as? String, "auto")

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertEqual(
            names, ["get_agenda", "get_project", "list_open_loops", "list_projects", "read_note", "search_notes"])
        for tool in tools {
            XCTAssertEqual(tool["strict"] as? Bool, true)
            let schema = try XCTUnwrap(tool["input_schema"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            XCTAssertNotNil(schema["required"] as? [String])
        }
        let loopsSchema = tools[2]["input_schema"] as? [String: Any]
        XCTAssertEqual(loopsSchema?["required"] as? [String], [])

        let system = try XCTUnwrap(body["system"] as? [[String: Any]])
        XCTAssertEqual(system.count, 2)
        XCTAssertNil(system[0]["cache_control"])
        XCTAssertEqual((system[1]["cache_control"] as? [String: Any])?["type"] as? String, "ephemeral")
        XCTAssertTrue((system[0]["text"] as? String ?? "").contains("read-only"))
        XCTAssertTrue((system[1]["text"] as? String ?? "").contains("Never write to the root."))
        let systemText = system.compactMap { $0["text"] as? String }.joined()
        XCTAssertFalse(systemText.contains("2026-11-12"))
        XCTAssertFalse(systemText.contains("America/Chicago"))

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let opening = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        let contextText = opening.first?["text"] as? String ?? ""
        XCTAssertTrue(contextText.contains("2026-11-12"))
        XCTAssertTrue(contextText.contains("Thursday"))
        XCTAssertTrue(contextText.contains("America/Chicago"))
        XCTAssertEqual(opening.last?["text"] as? String, "What's due today?")
    }

    func testCachedPrefixIsByteStableAcrossSessions() {
        let first = makeSession(FakeAgentTransport(), vaultAgents: "rules")
        let second = makeSession(FakeAgentTransport(), vaultAgents: "rules")
        XCTAssertEqual(JSONValue.array(first.tools).encoded(), JSONValue.array(second.tools).encoded())
        XCTAssertEqual(JSONValue.array(first.system).encoded(), JSONValue.array(second.system).encoded())
    }

    func testToolLoopRunsEveryToolAndSendsAllResultsInOneUserMessage() async throws {
        let transport = FakeAgentTransport([
            .success(
                agentResponse(
                    [
                        .thinking("", signature: "sig-1"),
                        toolCall("toolu_1", "search_notes", #"{"query":"alpha","limit":5}"#),
                        toolCall("toolu_2", "get_agenda", #"{"day":"2026-11-12"}"#),
                    ], stop: "tool_use")),
            .success(agentResponse([.text("Alpha ships the beta (01-projects/alpha/hub.md).")], stop: "end_turn")),
        ])
        let session = makeSession(transport)
        await ask(session, "Where is alpha?")

        XCTAssertNil(session.error)
        XCTAssertEqual(Set(context.calls), ["search_notes(alpha, 5)", "get_agenda(2026-11-12)"])
        XCTAssertEqual(transport.requests.count, 2)
        let second = transport.requests[1].messages
        XCTAssertEqual(second.map(\.role), [.user, .assistant, .user])
        let results = try second[2].content.map { try XCTUnwrap(parseJSONObject($0)) }
        XCTAssertEqual(results.compactMap { $0["type"] as? String }, ["tool_result", "tool_result"])
        XCTAssertEqual(results.compactMap { $0["tool_use_id"] as? String }, ["toolu_1", "toolu_2"])
        XCTAssertTrue((results[0]["content"] as? String ?? "").contains("01-projects/alpha/hub.md"))
        XCTAssertNil(results[0]["is_error"])

        XCTAssertEqual(session.transcript.count, 4)
        let turn = try XCTUnwrap(session.turns.first)
        XCTAssertEqual(turn.answer, "Alpha ships the beta (01-projects/alpha/hub.md).")
        XCTAssertEqual(turn.toolCalls.map(\.name), ["search_notes", "get_agenda"])
        XCTAssertEqual(turn.toolCalls[0].arguments, #"{"query":"alpha","limit":5}"#)
        XCTAssertTrue(turn.citations.contains(ToolCitation(kind: .path, value: "01-projects/alpha/hub.md")))
        XCTAssertTrue(turn.citations.contains(ToolCitation(kind: .record, value: "event-1")))
        XCTAssertFalse(session.isStreaming)
    }

    func testInvalidToolInputIsAnsweredWithAnErrorAndNotRun() async throws {
        let transport = FakeAgentTransport([
            .success(
                agentResponse(
                    [
                        toolCall("toolu_1", "read_note", #"{"path":"a.md","max_bytes":"lots"}"#),
                        toolCall("toolu_2", "delete_note", #"{"path":"a.md"}"#),
                        toolCall("toolu_3", "get_project", #"{"slug":"alpha","extra":1}"#),
                    ], stop: "tool_use")),
            .success(agentResponse([.text("Sorry.")], stop: "end_turn")),
        ])
        let session = makeSession(transport)
        await ask(session, "Read a.md")

        XCTAssertTrue(context.calls.isEmpty)
        let results = try transport.requests[1].messages[2].content.map { try XCTUnwrap(parseJSONObject($0)) }
        XCTAssertEqual(results.compactMap { $0["is_error"] as? Bool }, [true, true, true])
        XCTAssertEqual(results[0]["content"] as? String, "\"max_bytes\" must be a whole number.")
        XCTAssertEqual(results[1]["content"] as? String, "There is no tool named delete_note.")
        XCTAssertEqual(results[2]["content"] as? String, "Unknown argument \"extra\".")
    }

    func testToolRoundsStopAtEight() async throws {
        let transport = FakeAgentTransport()
        transport.whenScriptEnds = { index in
            .success(agentResponse([toolCall("toolu_\(index)", "get_project", #"{"slug":"alpha"}"#)], stop: "tool_use"))
        }
        let session = makeSession(transport)
        await ask(session, "Dig forever")

        XCTAssertEqual(context.calls.count, 8)
        XCTAssertEqual(transport.requests.count, 9)
        let lastResults = try XCTUnwrap(transport.requests.last?.messages.last?.content)
        let note = try XCTUnwrap(parseJSONObject(try XCTUnwrap(lastResults.last)))
        XCTAssertEqual(note["text"] as? String, AssistantSession.lastRoundNote)
        XCTAssertTrue(session.error?.contains("8") == true)
        XCTAssertTrue(session.transcript.isEmpty)
        XCTAssertTrue(session.turns.isEmpty)
    }

    func testRefusalShowsTheCategoryAndRunsNoTools() async {
        let transport = FakeAgentTransport([
            .success(
                agentResponse(
                    [toolCall("toolu_1", "search_notes", #"{"query":"x","limit":3}"#)], stop: "refusal",
                    category: "cyber"))
        ])
        let session = makeSession(transport)
        await ask(session, "Something declined")

        XCTAssertTrue(context.calls.isEmpty)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(session.error, "Claude declined this request (category: cyber). Nothing from it was kept.")
        XCTAssertTrue(session.transcript.isEmpty)
        XCTAssertTrue(session.turns.isEmpty)
    }

    func testMaxTokensRunsNoTools() async {
        let transport = FakeAgentTransport([
            .success(agentResponse([toolCall("toolu_1", "get_project", #"{"slug":"al"#)], stop: "max_tokens"))
        ])
        let session = makeSession(transport)
        await ask(session, "Long one")

        XCTAssertTrue(context.calls.isEmpty)
        XCTAssertTrue(session.error?.contains("length limit") == true)
        XCTAssertTrue(session.transcript.isEmpty)
    }

    func testAssistantTurnWithThinkingIsReplayedByteForByte() async throws {
        // Unusual key order and spacing: re-encoding would change these bytes.
        let thinkingBytes = Data(
            #"{"signature": "EqQBCkYIBRgCKkB+/x==", "type":"thinking", "thinking": "Plan: answer."}"#.utf8)
        let thinking = try XCTUnwrap(AgentContentBlock(raw: thinkingBytes))
        let transport = FakeAgentTransport([
            .success(agentResponse([thinking, .text("First answer.")], stop: "end_turn")),
            .success(agentResponse([.text("Second answer.")], stop: "end_turn")),
        ])
        let session = makeSession(transport)
        await ask(session, "First?")
        let afterFirst = session.transcript
        await ask(session, "Second?")

        let replayed = transport.requests[1]
        XCTAssertEqual(Array(replayed.messages.prefix(2)), afterFirst)
        XCTAssertEqual(replayed.messages[1].content.first, thinkingBytes)
        XCTAssertTrue(replayed.body().containsBytes(thinkingBytes))
        // The earlier turns render to the same bytes in both requests.
        let firstPrefix = JSONValue.array(transport.requests[0].messages.map(\.json)).encoded().dropLast()
        XCTAssertTrue(replayed.body().containsBytes(Data(firstPrefix)))
        XCTAssertEqual(Array(session.transcript.prefix(2)), afterFirst)
        XCTAssertEqual(session.turns.map(\.answer), ["First answer.", "Second answer."])
    }

    func testFailedTurnLeavesTheTranscriptAsItWas() async throws {
        let transport = FakeAgentTransport([
            .success(agentResponse([.text("One.")], stop: "end_turn")),
            .success(agentResponse([toolCall("toolu_1", "get_project", #"{"slug":"alpha"}"#)], stop: "tool_use")),
            .failure(AgentError.http(status: 529, errorType: nil, retryAfter: nil)),
        ])
        let session = makeSession(transport)
        await ask(session, "One?")
        let before = session.transcript
        await ask(session, "Two?")

        XCTAssertEqual(session.transcript, before)
        XCTAssertEqual(session.turns.count, 1)
        XCTAssertEqual(session.error, "Anthropic is overloaded right now. Try again in a moment.")
        XCTAssertFalse(session.isStreaming)
        XCTAssertEqual(session.liveText, "")
    }

    func testMissingKeyAsksForSetupAndSendsNothing() async {
        keys.key = nil
        let transport = FakeAgentTransport()
        let session = makeSession(transport)
        await ask(session, "Hello")

        XCTAssertEqual(session.error, "Add your Anthropic API key in Settings → AI.")
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertFalse(session.isStreaming)
    }

    func testStopCancelsWithoutAnErrorOrATurn() async {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Late.")], stop: "end_turn"))])
        transport.delay = .seconds(5)
        let session = makeSession(transport)
        session.send("Slow?")
        XCTAssertTrue(session.isStreaming)
        XCTAssertEqual(session.pendingQuestion, "Slow?")
        session.stop()
        await session.waitForCompletion()

        XCTAssertNil(session.error)
        XCTAssertTrue(session.turns.isEmpty)
        XCTAssertTrue(session.transcript.isEmpty)
        XCTAssertFalse(session.isStreaming)
    }

    func testPauseTurnContinuesWithoutAddingAUserMessage() async {
        let transport = FakeAgentTransport([
            .success(agentResponse([.text("Working…")], stop: "pause_turn")),
            .success(agentResponse([.text("Done.")], stop: "end_turn")),
        ])
        let session = makeSession(transport)
        await ask(session, "Long task")

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[1].messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(session.turns.first?.answer, "Working…\n\nDone.")
    }

    func testStreamedTextIsPublishedWhileTheTurnRuns() async {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Hi there")], stop: "end_turn"))])
        transport.updates = [.text("Hi"), .text(" there")]
        transport.delay = .milliseconds(200)
        let session = makeSession(transport)
        session.send("Hello")
        for _ in 0..<100 where session.liveText != "Hi there" { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(session.liveText, "Hi there")
        await session.waitForCompletion()
        XCTAssertEqual(session.liveText, "")
        XCTAssertEqual(session.turns.first?.answer, "Hi there")
    }
}

// Smaller checks, kept in an extension so the main test class stays readable.
@MainActor
extension AssistantSessionTests {
    func testFallbackModelIsReportedOnTheTurn() async {
        let transport = FakeAgentTransport([
            .success(agentResponse([.text("Answer.")], stop: "end_turn", model: "claude-opus-4-8"))
        ])
        let session = makeSession(transport)
        await ask(session, "Q")
        XCTAssertEqual(session.turns.first?.fallbackModel, "claude-opus-4-8")
    }

    func testClearStartsOver() async {
        let transport = FakeAgentTransport([.success(agentResponse([.text("A.")], stop: "end_turn"))])
        let session = makeSession(transport)
        await ask(session, "Q")
        session.clear()
        XCTAssertTrue(session.turns.isEmpty)
        XCTAssertTrue(session.transcript.isEmpty)
    }

    func testAnEmptyAnswerIsNotKept() async {
        let transport = FakeAgentTransport([.success(agentResponse([], stop: "end_turn"))])
        let session = makeSession(transport)
        await ask(session, "Q")
        XCTAssertEqual(session.error, "The Assistant returned an empty answer. Try again.")
        XCTAssertTrue(session.transcript.isEmpty)
    }
}
