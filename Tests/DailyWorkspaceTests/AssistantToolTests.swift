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
        _ = try await run("list_open_loops", #"{"source":"local","status":"open"}"#)
        XCTAssertEqual(context.calls, ["search_notes(alpha, 25)", "list_open_loops(local, -, open)"])
    }

    func testListOpenLoopsCitesRecordIDsAndPaths() async throws {
        let (result, block) = try await run("list_open_loops", "{}")
        XCTAssertEqual(
            result.call.citations,
            [
                ToolCitation(kind: .record, value: "local:alpha-12"),
                ToolCitation(kind: .path, value: "01-projects/alpha/hub.md"),
            ])
        let content = block["content"] as? String ?? ""
        XCTAssertTrue(content.contains(#""status":"open""#))
        XCTAssertTrue(content.contains(#""observed_at":"#))
    }

    func testMailOpenLoopsNeverReachAssistantToolResultsOrProvider() async throws {
        let root = try makeTemporaryVault(self)
        let model = AppModel(dependencies: .test())
        let mailResponse = FakeMailResponseSource(
            .data(
                rows: [["private-mail-7", "Private mail subject", "flagged status: true"]], incomplete: false))
        let store = OpenLoopsStore(
            tasks: model.tasks, reminders: model.reminders, vaultRoot: root,
            makeMail: { MailOpenLoopReader(enabled: $0, responseSource: mailResponse) })
        await store.refresh()
        XCTAssertEqual(mailResponse.reads, 0, "Mail must not be read without consent")
        XCTAssertEqual(store.observations[.mail]?.state, .unauthorized)
        XCTAssertEqual(store.observations[.local]?.state, .empty)
        store.setMailEnabled(true)
        await store.refreshMail()
        XCTAssertEqual(mailResponse.reads, 1)
        XCTAssertEqual(store.observations[.mail]?.state, .populated)
        XCTAssertEqual(store.loops(authority: .mail, includeDone: true).map(\.title), ["Private mail subject"])
        XCTAssertEqual(store.loops(authority: .mail).first?.nativeStatus, "flagged status: true")

        let assistantContext = WorkspaceAssistantContext(
            vaultRoot: { root }, openLoops: store, projects: model.projects, luunaWork: model.luunaWork,
            calendarStore: FakeCalendarStore(),
            ledger: RestartLedger(url: root.appendingPathComponent("restart-ledger.jsonl")))
        let toolRunner = AssistantToolRunner(context: assistantContext)
        let all = await toolRunner.run(AgentToolUse(id: "all", name: "list_open_loops", input: Data("{}".utf8)))
        let allBlock = try XCTUnwrap(parseJSONObject(all.block))
        let allContent = allBlock["content"] as? String ?? ""
        XCTAssertFalse(all.call.isError)
        XCTAssertTrue(all.call.citations.isEmpty)
        XCTAssertFalse(allContent.contains("flagged status: true"))
        XCTAssertFalse(allContent.contains("mail:private-mail-7"))
        XCTAssertFalse(allContent.contains("private-mail-7"))
        XCTAssertFalse(allContent.contains(#""mail":"#))

        do {
            _ = try await assistantContext.openLoops(source: "mail", project: nil, status: nil)
            XCTFail("The context must refuse Mail even if the tool schema changes.")
        } catch let failure as ToolFailure {
            XCTAssertEqual(failure.message, "Mail is not available to the Assistant.")
        }
        let mail = await toolRunner.run(
            AgentToolUse(
                id: "mail", name: "list_open_loops", input: Data(#"{"source":"mail"}"#.utf8)))
        let mailBlock = try XCTUnwrap(parseJSONObject(mail.block))
        XCTAssertTrue(mail.call.isError)
        XCTAssertFalse((mailBlock["content"] as? String ?? "").contains("Private mail subject"))
        XCTAssertFalse((mailBlock["content"] as? String ?? "").contains("private-mail-7"))
        XCTAssertTrue(mail.call.citations.isEmpty)

        let keys = FakeKeyStore()
        keys.key = "sk-ant-test"
        let transport = FakeAgentTransport([
            .success(
                agentResponse(
                    [
                        toolCall("all", "list_open_loops", "{}"),
                        toolCall("mail", "list_open_loops", #"{"source":"mail"}"#),
                    ], stop: "tool_use")),
            .success(agentResponse([.text("Done.")], stop: "end_turn")),
        ])
        let session = AssistantSession(transport: transport, keyStore: keys, context: assistantContext)
        session.send("What is open?")
        await session.waitForCompletion()
        XCTAssertEqual(transport.requests.count, 2)
        let providerBody = transport.requests[1].body()
        for secret in ["Private mail subject", "flagged status: true", "mail:private-mail-7", "private-mail-7"] {
            XCTAssertFalse(providerBody.containsBytes(Data(secret.utf8)), secret)
        }
        let results = try transport.requests[1].messages[2].content.map { try XCTUnwrap(parseJSONObject($0)) }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[1]["is_error"] as? Bool, true)
        XCTAssertFalse((results[1]["content"] as? String ?? "").contains("Private mail subject"))
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
