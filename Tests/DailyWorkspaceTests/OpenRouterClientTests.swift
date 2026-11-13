import XCTest

@testable import DailyWorkspace

private let openRouterToolStream = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_or_1","type":"message","role":"assistant","model":"openai/gpt-4.1","content":[],"stop_reason":null}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Checking "}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"the project."}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: content_block_start
    data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_or_1","name":"get_project","input":{}}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"slug\\":\\""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"alpha\\"}"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":1}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}

    event: message_stop
    data: {"type":"message_stop"}


    """

final class OpenRouterClientTests: XCTestCase {
    private func client() -> OpenRouterClient {
        var client = OpenRouterClient()
        client.protocolClasses = [StubURLProtocol.self]
        return client
    }

    private func request(model: String = "openai/gpt-4.1", outputSchema: JSONValue? = nil) -> AgentRequest {
        AgentRequest(
            model: model, maxTokens: 4096, effort: .medium,
            system: [
                .object([
                    ("type", .string("text")), ("text", .string("Read-only assistant.")),
                    ("cache_control", .ephemeralCache),
                ])
            ],
            tools: [
                .object([
                    ("name", .string("get_project")), ("description", .string("Read project")),
                    ("strict", .bool(true)), ("cache_control", .ephemeralCache),
                    (
                        "input_schema",
                        .object([
                            ("type", .string("object")),
                            ("properties", .object([("slug", .object([("type", .string("string"))]))])),
                        ])
                    ),
                ])
            ],
            messages: [AgentMessage(role: .user, content: [AgentContentBlock.text("PRIVATE TEXT").raw])],
            outputSchema: outputSchema)
    }

    func testBearerEndpointGenericBodyAndStreamedToolCall() async throws {
        StubURLProtocol.serve(.init(body: Data(openRouterToolStream.utf8)))
        let updates = OpenRouterUpdateLog()
        let response = try await client().send(request(), apiKey: "router-secret") { await updates.add($0) }

        XCTAssertEqual(response.id, "msg_or_1")
        XCTAssertEqual(response.model, "openai/gpt-4.1")
        XCTAssertEqual(response.stopReason, "tool_use")
        XCTAssertEqual(response.text, "Checking the project.")
        XCTAssertEqual(response.toolUses.first?.id, "toolu_or_1")
        XCTAssertEqual(response.toolUses.first?.name, "get_project")
        XCTAssertEqual((response.toolUses.first?.input).flatMap(parseJSONObject)?["slug"] as? String, "alpha")
        let received = await updates.all
        XCTAssertEqual(received, [.text("Checking "), .text("the project."), .toolUse(name: "get_project")])

        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(sent.request.url, OpenRouterClient.defaultEndpoint)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "authorization"), "Bearer router-secret")
        XCTAssertNil(sent.request.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertNil(sent.request.value(forHTTPHeaderField: "anthropic-version"))
        XCTAssertNil(sent.request.value(forHTTPHeaderField: "anthropic-beta"))
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "accept"), "text/event-stream")
        XCTAssertEqual(sent.request.cachePolicy, .reloadIgnoringLocalCacheData)
        let body = try XCTUnwrap(parseJSONObject(sent.body))
        XCTAssertEqual(body["model"] as? String, "openai/gpt-4.1")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)
        for key in ["thinking", "fallbacks", "cache_control", "output_config", "tool_choice"] {
            XCTAssertNil(body[key], key)
        }
        let system = try XCTUnwrap(body["system"] as? [[String: Any]])
        XCTAssertNil(system[0]["cache_control"])
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools[0]["name"] as? String, "get_project")
        XCTAssertNil(tools[0]["strict"])
        XCTAssertNil(tools[0]["cache_control"])
    }

    func testSchemaAndClaudeBlocksStayOutOfGenericModelRequestButToolResultsRemain() throws {
        var draft = request(model: "google/gemini-2.5-pro", outputSchema: .object([("type", .string("object"))]))
        draft.messages = [
            AgentMessage(role: .user, content: [AgentContentBlock.text("start").raw]),
            AgentMessage(
                role: .assistant,
                content: [
                    AgentContentBlock.thinking("reason", signature: "private-signature").raw,
                    AgentContentBlock.text("Looking up.").raw,
                    AgentContentBlock.toolUse(
                        id: "call1", name: "get_project", inputJSON: Data(#"{"slug":"alpha"}"#.utf8)
                    ).raw,
                ]),
            AgentMessage(
                role: .user,
                content: [
                    Data(#"{"type":"tool_result","tool_use_id":"call1","content":"project found"}"#.utf8)
                ]),
        ]
        let body = try XCTUnwrap(parseJSONObject(client().urlRequest(for: draft, apiKey: "key").httpBody ?? Data()))
        XCTAssertEqual(body["model"] as? String, "google/gemini-2.5-pro")
        XCTAssertNil(body["output_config"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let assistant = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistant.compactMap { $0["type"] as? String }, ["text", "tool_use"])
        XCTAssertEqual(assistant[1]["id"] as? String, "call1")
        let result = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(result[0]["tool_use_id"] as? String, "call1")
        XCTAssertEqual(result[0]["content"] as? String, "project found")
        XCTAssertEqual(draft.messages[1].content.count, 3, "transport must not alter the stored transcript")
    }

    func testHTTPFailuresNameOpenRouterWithoutEchoingResponseBody() async {
        let body = Data(#"{"error":{"type":"overloaded_error","message":"PRIVATE TEXT"}}"#.utf8)
        for (status, kind) in [
            (401, AgentError.Kind.unauthorized), (404, .notFound), (429, .rateLimited), (503, .overloaded),
        ] {
            StubURLProtocol.serve(.init(status: status, body: body))
            do {
                _ = try await client().send(request(), apiKey: "key") { _ in }
                XCTFail("HTTP \(status) must throw")
            } catch {
                XCTAssertEqual((error as? AgentError)?.kind, kind)
                XCTAssertTrue(error.localizedDescription.contains("OpenRouter"))
                XCTAssertFalse(error.localizedDescription.contains("Anthropic"))
                XCTAssertFalse(error.localizedDescription.contains("PRIVATE TEXT"))
            }
        }
    }

    func testStreamErrorNamesOpenRouterWithoutEchoingResponseBody() async {
        let stream = """
            event: error
            data: {"type":"error","error":{"type":"rate_limit_error","message":"PRIVATE TEXT"}}


            """
        StubURLProtocol.serve(.init(body: Data(stream.utf8)))
        do {
            _ = try await client().send(request(), apiKey: "key") { _ in }
            XCTFail("stream error must throw")
        } catch {
            XCTAssertEqual((error as? AgentError)?.kind, .rateLimited)
            XCTAssertTrue(error.localizedDescription.contains("OpenRouter"))
            XCTAssertFalse(error.localizedDescription.contains("Anthropic"))
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE TEXT"))
        }
    }

    func testPreCancelledSendDoesNotOpenConnection() async {
        StubURLProtocol.serve(.init(body: Data(openRouterToolStream.utf8)))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client().send(request(), apiKey: "key") { _ in }
        }
        do {
            _ = try await task.value
            XCTFail("cancelled send must throw")
        } catch is CancellationError {
            XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        } catch {
            XCTFail("expected cancellation, received \(type(of: error))")
        }
    }
}

private actor OpenRouterUpdateLog {
    private var updates: [AgentStreamUpdate] = []
    func add(_ update: AgentStreamUpdate) { updates.append(update) }
    var all: [AgentStreamUpdate] { updates }
}
