import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

@MainActor
extension AssistantGoldenSetTests {
    private func assertNativeWorkReady(in model: AppModel) async throws {
        try await loadAtlasHub(in: model)
        model.projects.select("atlas")
        XCTAssertEqual(model.projects.detail?.hub.path, Self.hub)
        XCTAssertNil(model.projects.bindLuuna(origin: .standard, projectID: "atlas-native"))
        XCTAssertEqual(
            model.projects.detail?.association?.luuna,
            LuunaProjectBinding(origin: .standard, projectID: "atlas-native"))
        await model.luuna.refresh()
        XCTAssertEqual(model.luuna.selectedProject?.projectID, "atlas-native")
        for _ in 0..<400 {
            if model.luuna.projects.value?.map(\.id) == ["atlas-native"] { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(model.luuna.projects.value?.map(\.id), ["atlas-native"])
        await model.luunaWork.refresh()
        for _ in 0..<400 {
            if model.luunaWork.board.state == .populated && model.luunaWork.tickets.state == .populated {
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(model.luunaWork.observedProjectBinding?.projectID, "atlas-native")
        XCTAssertEqual(model.luunaWork.board.state, .populated)
        XCTAssertEqual(model.luunaWork.tickets.value?.first?.id, Self.nativeTicketID)
    }

    func testProjectToolCitesNativeTicketRatherThanCompletedRun() async throws {
        let root = try makeTemporaryVault(self)
        try copyFixture(into: root)
        let appRoot = try makeTemporaryVault(self)
        let runtimeReader = FakeLuunaReader()
        let nativeProjects = try JSONDecoder().decode(
            [LuunaProjectRecord].self,
            from: Data(#"[{"id":"atlas-native","name":"Atlas native","revision":1}]"#.utf8))
        runtimeReader.set("projects", .success(nativeProjects))
        let nativeProject = try JSONDecoder().decode(
            LuunaProjectView.self,
            from: Data(
                #"{"project":{"id":"atlas-native","name":"Atlas native","revision":1},"repositories":[],"manifest":null,"discovery":null}"#
                    .utf8))
        runtimeReader.set("project", .success(nativeProject))
        let board = try JSONDecoder().decode(
            LuunaBoard.self,
            from: Data(
                """
                {"columns":[{"column":{"id":"review","title":"Review"},"cards":[
                  {"column":"review","kind":"ticket","project_id":"atlas-native","title":"Publish Atlas index",
                   "ticket_id":"\(Self.nativeTicketID)","run_id":"atlas-run-done","state":"completed"}]}]}
                """.utf8))
        let tickets = try JSONDecoder().decode(
            [LuunaTicketRecord].self,
            from: Data(
                """
                [{"id":"\(Self.nativeTicketID)","project_id":"atlas-native","revision":1,
                  "title":"Publish Atlas index","status":"open"}]
                """.utf8))
        let reader = FakeLuunaWorkReader()
        reader.set("board", .success(board))
        reader.set("tickets", .success(tickets))
        let luunaKeys = FakeKeyStore()
        luunaKeys.key = "synthetic-luuna-token"
        let assistantKeys = FakeKeyStore()
        assistantKeys.key = "synthetic-assistant-key"
        let model = AppModel(
            dependencies: .test(
                directory: WorkspaceDirectory(url: appRoot), luunaReader: runtimeReader,
                luunaWorkReader: reader, luunaKeys: luunaKeys))
        model.useVault(at: root)
        try await assertNativeWorkReady(in: model)

        let transport = FakeAgentTransport([
            .success(
                agentResponse(
                    [toolCall("native_project", "get_project", #"{"slug":"atlas"}"#)], stop: "tool_use")),
            .success(
                agentResponse([.text("No. The publishing ticket remains open (atlas-publish-42).")], stop: "end_turn")),
        ])
        let session = AssistantSession(
            transport: transport, keyStore: assistantKeys, context: model.assistantContext,
            configuration: AssistantTestClock.configuration, isEnabled: true)
        session.send("Did the completed run close the publishing ticket?")
        await session.waitForCompletion()
        XCTAssertNil(session.error)
        XCTAssertEqual(transport.requests.count, 2)
        let turn = try XCTUnwrap(session.turns.first)
        let ticketCitation = ToolCitation(kind: .record, value: Self.nativeTicketID)
        XCTAssertTrue(turn.citations.contains(ticketCitation))
        XCTAssertFalse(turn.citations.contains(.init(kind: .record, value: "atlas-run-done")))
        let result = try XCTUnwrap(transport.requests.last?.messages.last?.content.first)
        let block = try XCTUnwrap(parseJSONObject(result))
        let content = try XCTUnwrap(block["content"] as? String)
        let payload = try XCTUnwrap(parseJSONObject(Data(content.utf8)))
        let nativeTickets = try XCTUnwrap(payload["native_tickets"] as? [[String: Any]])
        let ticket = try XCTUnwrap(nativeTickets.first { $0["id"] as? String == Self.nativeTicketID })
        XCTAssertEqual(ticket["status"] as? String, "open")
        XCTAssertEqual(ticket["source"] as? String, "luuna")
        XCTAssertEqual(ticket["board_column"] as? String, "review")
    }

    func testProjectHubRemainsCiteableWhenBoundNativeWorkIsUnavailable() async throws {
        let root = try makeTemporaryVault(self)
        try copyFixture(into: root)
        let appRoot = try makeTemporaryVault(self)
        let model = AppModel(dependencies: .test(directory: WorkspaceDirectory(url: appRoot)))
        model.useVault(at: root)
        try await loadAtlasHub(in: model)
        model.projects.select("atlas")
        XCTAssertNil(model.projects.bindLuuna(origin: .standard, projectID: "atlas-native"))

        let result = await AssistantToolRunner(context: model.assistantContext).run(
            AgentToolUse(id: "offline_project", name: "get_project", input: Data(#"{"slug":"atlas"}"#.utf8)))
        XCTAssertFalse(result.call.isError, result.call.errorMessage ?? "")
        let block = try XCTUnwrap(parseJSONObject(result.block))
        let content = try XCTUnwrap(block["content"] as? String)
        let project = try XCTUnwrap(parseJSONObject(Data(content.utf8)))
        XCTAssertEqual(project["hub_path"] as? String, Self.hub)
        XCTAssertEqual((project["native_tickets"] as? [Any])?.count, 0)
        XCTAssertTrue((project["native_tickets_unavailable"] as? String)?.contains("unknown, not empty") == true)
        XCTAssertTrue(result.call.citations.contains(.init(kind: .path, value: Self.hub)))
        XCTAssertFalse(result.call.citations.contains { $0.kind == .record && $0.value == Self.nativeTicketID })
    }
}
