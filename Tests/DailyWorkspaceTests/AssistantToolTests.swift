import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class AssistantToolTests: XCTestCase {
    private var context: FakeAssistantContext!
    private var runner: AssistantToolRunner!

    override func setUp() async throws {
        context = FakeAssistantContext()
        runner = AssistantToolRunner(context: context)
    }

    private func run(_ name: String, _ input: String) async throws -> (ToolRunResult, [String: Any]) {
        let result = await runner.run(AgentToolUse(id: "toolu_x", name: name, input: Data(input.utf8)))
        return (result, try XCTUnwrap(parseJSONObject(result.block)))
    }

    func testReadNoteIsCutToMaxBytesOnACharacterBoundary() async throws {
        context.note = ToolNote(path: "a.md", text: "héllo wörld", truncated: false)
        let (result, block) = try await run("read_note", #"{"path":"a.md","max_bytes":3}"#)

        XCTAssertFalse(result.call.isError)
        XCTAssertEqual(context.calls, ["read_note(a.md, 3)"])
        let note = try XCTUnwrap(parseJSONObject(Data((block["content"] as? String ?? "").utf8)))
        XCTAssertEqual(note["text"] as? String, "hé")
        XCTAssertEqual(note["truncated"] as? Bool, true)
        XCTAssertEqual(result.call.citations, [ToolCitation(kind: .path, value: "a.md")])
    }

    func testLimitsAreClampedAndFiltersPassedThrough() async throws {
        _ = try await run("search_notes", #"{"query":"alpha","limit":500}"#)
        _ = try await run("list_open_loops", #"{"source":"org","status":"TODO"}"#)
        XCTAssertEqual(context.calls, ["search_notes(alpha, 25)", "list_open_loops(org, -, TODO)"])
    }

    func testListOpenLoopsCitesRecordIDsAndPaths() async throws {
        let (result, block) = try await run("list_open_loops", "{}")
        XCTAssertEqual(
            result.call.citations,
            [
                ToolCitation(kind: .record, value: "seeds:alpha-12"),
                ToolCitation(kind: .path, value: ".seeds/issues.jsonl"),
            ])
        let content = block["content"] as? String ?? ""
        XCTAssertTrue(content.contains(#""status":"in_progress""#))
        XCTAssertTrue(content.contains(#""observed_at":"#))
    }

    func testBadInputAndSourceFailuresBecomeErrorResults() async throws {
        let (badSource, badSourceBlock) = try await run("list_open_loops", #"{"source":"luuna"}"#)
        XCTAssertTrue(badSource.call.isError)
        XCTAssertEqual(badSourceBlock["is_error"] as? Bool, true)

        let (badDay, _) = try await run("get_agenda", #"{"day":"2026-02-30"}"#)
        XCTAssertEqual(badDay.call.errorMessage, "day must be a date like 2026-11-12.")

        let (missing, _) = try await run("get_project", "{}")
        XCTAssertEqual(missing.call.errorMessage, "Missing required argument \"slug\".")

        let invalid = await runner.run(AgentToolUse(id: "t", name: "read_note", input: nil))
        XCTAssertTrue(invalid.call.isError)

        context.failure = TestFailure("The vault is unavailable.")
        let (unavailable, block) = try await run("get_project", #"{"slug":"alpha"}"#)
        XCTAssertTrue(unavailable.call.isError)
        XCTAssertEqual(block["content"] as? String, "The vault is unavailable.")
        XCTAssertEqual(context.calls.count, 1)
    }

    // MARK: Restart drafts

    func testRestartDraftUsesStructuredOutputAtMediumEffortAndLeavesTheTranscriptAlone() async throws {
        let keys = FakeKeyStore()
        keys.key = "sk-ant-test"
        let draftJSON = """
            {"decision":"Ship the beta first.","next_action":"Open hub.md and write the release note.",\
            "notes":"","sources_read":["01-projects/alpha/hub.md","made/up.md"]}
            """
        let transport = FakeAgentTransport([
            .success(
                agentResponse([toolCall("toolu_1", "read_note", #"{"path":"x.md","max_bytes":100}"#)], stop: "tool_use")
            ),
            .success(agentResponse([.text("Read it.")], stop: "end_turn")),
            .success(agentResponse([.text(draftJSON)], stop: "end_turn")),
        ])
        context.note = ToolNote(path: "01-projects/alpha/hub.md", text: "Alpha", truncated: false)
        let session = AssistantSession(
            transport: transport, keyStore: keys, context: context, configuration: AssistantTestClock.configuration)
        session.send("Read the alpha hub")
        await session.waitForCompletion()
        let before = session.transcript

        let draft = try await session.draftRestartRecord(project: "alpha")

        XCTAssertEqual(session.transcript, before)
        XCTAssertEqual(session.turns.count, 1)
        XCTAssertFalse(session.isStreaming)
        XCTAssertEqual(draft.projectSlug, "alpha")
        XCTAssertEqual(draft.createdAt, AssistantTestClock.now)
        XCTAssertEqual(draft.decision, "Ship the beta first.")
        XCTAssertEqual(draft.nextAction, "Open hub.md and write the release note.")
        XCTAssertEqual(
            draft.sources,
            [.init(path: "01-projects/alpha/hub.md", observed: true), .init(path: "made/up.md", observed: false)])

        let body = transport.requests[2].parsedBody
        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "medium")
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(transport.requests[2].messages.count, before.count + 1)
        XCTAssertEqual(Array(transport.requests[2].messages.prefix(before.count)), before)

        let record = draft.accepted(
            at: AssistantTestClock.now,
            sources: [SourceRef(path: "01-projects/alpha/hub.md", sha256: "abc", observedAt: AssistantTestClock.now)])
        XCTAssertEqual(record.projectSlug, "alpha")
        XCTAssertEqual(record.nextAction, draft.nextAction)
    }

    func testAnUnreadableDraftIsAnError() async {
        let keys = FakeKeyStore()
        keys.key = "k"
        let transport = FakeAgentTransport([.success(agentResponse([.text("not json")], stop: "end_turn"))])
        let session = AssistantSession(transport: transport, keyStore: keys, context: context)
        do {
            _ = try await session.draftRestartRecord(project: "alpha")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? AgentError)?.kind, .invalidDraft)
        }
        XCTAssertFalse(session.isStreaming)
    }
}
