import XCTest

@testable import DailyWorkspace

/// A recorded Messages API stream: thinking with a signature, streamed text, and a tool call whose input arrives
/// in `input_json_delta` fragments.
private let recordedStream = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":12,"output_tokens":1}}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Look it up."}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQBCkYI+/x=="}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: ping
    data: {"type": "ping"}

    event: content_block_start
    data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Checking "}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"your \\"notes\\"."}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":1}

    event: content_block_start
    data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_01","name":"search_notes","input":{}}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\": \\"al"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"pha\\", \\"limit\\": 5}"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":2}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":40}}

    event: message_stop
    data: {"type":"message_stop"}


    """

final class AnthropicClientTests: XCTestCase {
    private struct Accumulated {
        var response: AgentResponse
        var updates: [AgentStreamUpdate] = []
        var complete = false
    }

    private func accumulate(_ stream: String) throws -> Accumulated {
        var accumulator = MessageStreamAccumulator()
        var updates: [AgentStreamUpdate] = []
        for event in SSEParser.events(in: Data(stream.utf8)) {
            if let update = try accumulator.apply(event) { updates.append(update) }
        }
        return Accumulated(response: accumulator.finalResponse(), updates: updates, complete: accumulator.isComplete)
    }

    func testRecordedStreamBuildsThinkingTextAndToolUse() throws {
        let result = try accumulate(recordedStream)
        let (response, updates, complete) = (result.response, result.updates, result.complete)

        XCTAssertTrue(complete)
        XCTAssertEqual(response.id, "msg_01")
        XCTAssertEqual(response.model, "claude-opus-5-5")
        XCTAssertEqual(response.stopReason, "tool_use")
        XCTAssertEqual(response.content.map(\.type), ["thinking", "text", "tool_use"])
        XCTAssertEqual(
            utf8Text(response.content[0].raw),
            #"{"type":"thinking","thinking":"Look it up.","signature":"EqQBCkYI+/x=="}"#)
        XCTAssertEqual(response.text, #"Checking your "notes"."#)
        XCTAssertEqual(updates, [.text("Checking "), .text(#"your "notes"."#), .toolUse(name: "search_notes")])

        let use = try XCTUnwrap(response.toolUses.first)
        XCTAssertEqual(use.id, "toolu_01")
        XCTAssertEqual(use.name, "search_notes")
        XCTAssertEqual(utf8Text(try XCTUnwrap(use.input)), #"{"query": "alpha", "limit": 5}"#)
        let block = try XCTUnwrap(parseJSONObject(response.content[2].raw))
        XCTAssertEqual((block["input"] as? [String: Any])?["query"] as? String, "alpha")
    }

    func testSSEParserHandlesCarriageReturnsCommentsAndAMissingFinalBlankLine() {
        let events = SSEParser.events(in: Data(": keep-alive\r\nevent: a\r\ndata: 1\r\n\r\ndata: 2\ndata: 3".utf8))
        XCTAssertEqual(events, [SSEEvent(name: "a", data: "1"), SSEEvent(name: nil, data: "2\n3")])
    }

    func testInvalidToolJSONIsStoredAsAnEmptyObjectAndFlagged() throws {
        let stream = """
            data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"read_note","input":{}}}

            data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"path\\": "}}

            data: {"type":"content_block_stop","index":0}


            """
        let result = try accumulate(stream)
        let response = result.response
        XCTAssertFalse(result.complete)
        XCTAssertNil(response.toolUses.first?.input)
        XCTAssertEqual(
            utf8Text(response.content[0].raw),
            #"{"type":"tool_use","id":"t","name":"read_note","input":{}}"#)
    }

    func testRefusalStopDetailsAreRead() throws {
        let stream = """
            data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"category":"bio"}}}

            data: {"type":"message_stop"}


            """
        let response = try accumulate(stream).response
        XCTAssertEqual(response.stopReason, "refusal")
        XCTAssertEqual(response.stopDetails?.category, "bio")
    }

    func testStreamErrorEventIsAPlainMessage() {
        let stream =
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"secret note text"}}"# + "\n\n"
        XCTAssertThrowsError(try accumulate(stream)) { error in
            XCTAssertEqual((error as? AgentError)?.kind, .overloaded)
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
    }

    func testFallbackDropsModelInternalBlocksBeforeTheSwitchPoint() throws {
        let fallback = try XCTUnwrap(
            AgentContentBlock(raw: Data(#"{"type":"fallback","from":{"model":"a"},"to":{"model":"b"}}"#.utf8)))
        let response = agentResponse(
            [
                .thinking("x", signature: "s"), .text("Partial "), toolCall("t1", "get_project", #"{"slug":"a"}"#),
                fallback, .thinking("y", signature: "s2"), toolCall("t2", "get_project", #"{"slug":"b"}"#),
            ], stop: "tool_use")
        XCTAssertEqual(response.replayableContent.map(\.type), ["text", "fallback", "thinking", "tool_use"])
        XCTAssertEqual(response.toolUses.map(\.id), ["t2"])
    }

    // MARK: HTTP

    private func client() -> AnthropicClient {
        var client = AnthropicClient()
        client.protocolClasses = [StubURLProtocol.self]
        return client
    }

    private func request() -> AgentRequest {
        AgentRequest(
            model: "claude-opus-5-5", maxTokens: 16_000, effort: .low, system: AssistantPrompt.system(vaultAgents: nil),
            tools: AssistantTool.definitions,
            messages: [AgentMessage(role: .user, content: [AgentContentBlock.text("SECRET USER TEXT").raw])],
            outputSchema: nil)
    }

    func testClientSendsTheRightHeadersAndParsesTheStream() async throws {
        StubURLProtocol.serve(.init(body: Data(recordedStream.utf8)))
        let collected = UpdateLog()
        let response = try await client().send(request(), apiKey: "sk-ant-test") { await collected.add($0) }

        XCTAssertEqual(response.stopReason, "tool_use")
        XCTAssertEqual(response.toolUses.count, 1)
        let count = await collected.count
        XCTAssertEqual(count, 3)
        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url, AnthropicClient.defaultEndpoint)
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "content-type"), "application/json")
        let body = try XCTUnwrap(parseJSONObject(sent.body))
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["temperature"])
    }

    func testHTTPErrorsArePlainAndNeverEchoTheBody() async {
        let body = Data(#"{"type":"error","error":{"type":"overloaded_error","message":"SECRET USER TEXT"}}"#.utf8)
        struct Case {
            let status: Int
            var headers: [String: String] = [:]
            let kind: AgentError.Kind
            let message: String
        }
        let cases = [
            Case(
                status: 401, kind: .unauthorized, message: "Anthropic rejected the API key. Check it in Settings → AI."),
            Case(
                status: 429, headers: ["retry-after": "30"], kind: .rateLimited,
                message: "Anthropic's rate limit was reached. Try again in 30 seconds."),
            Case(status: 529, kind: .overloaded, message: "Anthropic is overloaded right now. Try again in a moment."),
            Case(status: 503, kind: .overloaded, message: "Anthropic is overloaded right now. Try again in a moment."),
            Case(status: 400, kind: .badRequest, message: "Anthropic rejected the request as invalid (HTTP 400)."),
        ]
        for item in cases {
            let (status, kind, message) = (item.status, item.kind, item.message)
            StubURLProtocol.serve(.init(status: status, headers: item.headers, body: body))
            do {
                _ = try await client().send(request(), apiKey: "k") { _ in }
                XCTFail("HTTP \(status) should throw")
            } catch {
                XCTAssertEqual((error as? AgentError)?.kind, kind, "HTTP \(status)")
                XCTAssertEqual(error.localizedDescription, message, "HTTP \(status)")
                XCTAssertFalse(error.localizedDescription.contains("SECRET"))
            }
        }
    }

    func testAStreamThatEndsEarlyIsAnError() async {
        let partial = recordedStream.components(separatedBy: "event: message_delta").first ?? ""
        StubURLProtocol.serve(.init(body: Data(partial.utf8)))
        do {
            _ = try await client().send(request(), apiKey: "k") { _ in }
            XCTFail("an unfinished stream should throw")
        } catch {
            XCTAssertEqual((error as? AgentError)?.kind, .incomplete)
        }
    }

    func testADroppedConnectionIsRetryableButBeingOfflineIsNot() {
        let dropped = AgentError.network(URLError(.networkConnectionLost))
        XCTAssertEqual(dropped.kind, .network)
        XCTAssertTrue(AgentRetryPolicy().isRetryable(dropped))
        let offline = AgentError.network(URLError(.notConnectedToInternet))
        XCTAssertEqual(offline.kind, .offline)
        XCTAssertFalse(AgentRetryPolicy().isRetryable(offline))
    }
}

private actor UpdateLog {
    private var updates: [AgentStreamUpdate] = []
    func add(_ update: AgentStreamUpdate) { updates.append(update) }
    var count: Int { updates.count }
}
