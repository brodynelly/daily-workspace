import DailyCore
import XCTest

@testable import DailyWorkspace

private struct TicketOnlyReader: LuunaWorkReading {
    func board(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaBoard {
        throw LuunaReadFailure.unavailable(.notChecked)
    }

    func tickets(_ projectID: String, _ connection: LuunaConnection) async throws -> [LuunaTicketRecord] {
        try JSONDecoder().decode(
            [LuunaTicketRecord].self,
            from: Data(
                #"[{"id":"native-1","project_id":"native-project","revision":1,"title":"Native work","status":"open"}]"#
                    .utf8))
    }

    func showTicket(_ ticketID: String, _ connection: LuunaConnection) async throws -> LuunaTicketRecord {
        throw LuunaReadFailure.unavailable(.notChecked)
    }

    func home(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaHome {
        throw LuunaReadFailure.unavailable(.notChecked)
    }

    func homeAll(_ connection: LuunaConnection) async throws -> LuunaHome {
        throw LuunaReadFailure.unavailable(.notChecked)
    }

    func runs(_ projectID: String, _ connection: LuunaConnection) async throws -> [LuunaRunRecord] {
        throw LuunaReadFailure.unavailable(.notChecked)
    }

    func run(_ runID: String, _ connection: LuunaConnection) async throws -> LuunaRunRecord {
        throw LuunaReadFailure.unavailable(.notChecked)
    }
}

@MainActor
final class AssistantProjectInventoryTests: XCTestCase {
    private func run(_ context: AssistantContext, input: String = "{}") async throws -> (ToolRunResult, [String: Any]) {
        let runner = AssistantToolRunner(context: context)
        let result = await runner.run(
            AgentToolUse(id: "inventory", name: "list_projects", input: Data(input.utf8)))
        return (result, try XCTUnwrap(parseJSONObject(result.block)))
    }

    private func payload(_ block: [String: Any]) throws -> [String: Any] {
        let content = try XCTUnwrap(block["content"] as? String)
        return try XCTUnwrap(parseJSONObject(Data(content.utf8)))
    }

    private func selectedVault(_ root: URL) async throws -> WorkspaceAssistantContext {
        // Isolate the hub observation from AppModel's asynchronous vault observer: a second refresh can
        // discard a first read before a full-suite test reaches the tool.
        let shell = AppModel(dependencies: .test())
        let directory = try makeTemporaryVault(self)
        let projects = ProjectsStore(
            registry: AssociationRegistry(directory: WorkspaceDirectory(url: directory)),
            luuna: nil, vaultRoot: root)
        await projects.refresh()
        return WorkspaceAssistantContext(
            vaultRoot: { root }, openLoops: shell.openLoops, projects: projects, luunaWork: shell.luunaWork,
            calendarStore: FakeCalendarStore(),
            ledger: RestartLedger(url: directory.appendingPathComponent("restart-ledger.jsonl")))
    }

    func testListsRegisteredHubsWithCiteablePathsAndReadsVaultNavigationNote() async throws {
        let root = try makeTemporaryVault(self)
        try write(
            "# Home\nSee the [project index](01-projects/index.md) for projects.\n",
            to: root.appendingPathComponent("home.md"))
        try write("# Project index\nSee Alpha and Beta.\n", to: root.appendingPathComponent("01-projects/index.md"))
        try write(
            "---\ntype: project\n---\n# Beta\nProject context, not a task status.\n",
            to: root.appendingPathComponent("01-projects/beta/beta.md"))
        try write(
            "---\ntype: project\n---\n# Alpha\nProject context, not a task status.\n",
            to: root.appendingPathComponent("01-projects/alpha/alpha.md"))
        let context = try await selectedVault(root)

        let (result, block) = try await run(context)
        XCTAssertFalse(result.call.isError)
        let payload = try XCTUnwrap(parseJSONObject(Data((block["content"] as? String ?? "").utf8)))
        XCTAssertEqual(payload["state"] as? String, "populated")
        XCTAssertEqual(payload["truncated"] as? Bool, false)
        let projects = try XCTUnwrap(payload["projects"] as? [[String: Any]])
        XCTAssertEqual(projects.compactMap { $0["slug"] as? String }, ["alpha", "beta"])
        XCTAssertEqual(projects.compactMap { $0["title"] as? String }, ["Alpha", "Beta"])
        XCTAssertEqual(
            projects.compactMap { $0["path"] as? String },
            ["01-projects/alpha/alpha.md", "01-projects/beta/beta.md"])
        XCTAssertEqual(
            result.call.citations,
            [
                ToolCitation(kind: .path, value: "01-projects/alpha/alpha.md"),
                ToolCitation(kind: .path, value: "01-projects/beta/beta.md"),
            ])
        let hits = try await context.searchNotes(query: "home", limit: 8)
        XCTAssertEqual(hits.first?.path, "home.md")
        let home = try await context.readNote(path: "home.md", maxBytes: 1_000)
        XCTAssertTrue(home.text.contains("01-projects/index.md"))
        XCTAssertTrue(AssistantPrompt.rules.contains("list_projects"))
        XCTAssertTrue(AssistantPrompt.rules.contains("navigation notes"))
        XCTAssertTrue(AssistantPrompt.rules.contains("domain map"))
        XCTAssertTrue(AssistantPrompt.rules.contains("private journals"))
        XCTAssertTrue(AssistantPrompt.rules.contains("full vault-relative links"))
    }

    func testUnavailableAndNotReadProjectSourcesAreNotReportedAsEmpty() async throws {
        let root = try makeTemporaryVault(self)
        let model = AppModel(dependencies: .test())
        let (notSelected, noVaultBlock) = try await run(model.assistantContext)
        XCTAssertEqual(try payload(noVaultBlock)["state"] as? String, "unavailable")
        XCTAssertTrue(notSelected.call.citations.isEmpty)

        let appDirectory = try makeTemporaryVault(self)
        let projects = ProjectsStore(
            registry: AssociationRegistry(directory: WorkspaceDirectory(url: appDirectory)),
            luuna: nil, vaultRoot: root)
        let notReadContext = WorkspaceAssistantContext(
            vaultRoot: { root }, openLoops: model.openLoops, projects: projects, luunaWork: model.luunaWork,
            calendarStore: FakeCalendarStore(),
            ledger: RestartLedger(url: appDirectory.appendingPathComponent("restart-ledger.jsonl")))
        let (notRead, preReadBlock) = try await run(notReadContext)
        XCTAssertEqual(try payload(preReadBlock)["state"] as? String, "not_read")
        XCTAssertTrue(notRead.call.citations.isEmpty)

        await projects.refresh()
        let (missingFolder, block) = try await run(notReadContext)
        let unavailable = try payload(block)
        XCTAssertEqual(unavailable["state"] as? String, "unavailable")
        XCTAssertEqual((unavailable["projects"] as? [Any])?.count, 0)
        XCTAssertTrue(missingFolder.call.citations.isEmpty)

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("01-projects"), withIntermediateDirectories: true)
        await projects.refresh()
        let (empty, emptyBlock) = try await run(notReadContext)
        let emptyPayload = try payload(emptyBlock)
        XCTAssertEqual(emptyPayload["state"] as? String, "empty")
        XCTAssertTrue(empty.call.citations.isEmpty)
    }

    func testInventoryRejectsArgumentsAndExcludesPrivateAndGeneratedHubs() async throws {
        let root = try makeTemporaryVault(self)
        let project = "---\ntype: project\n---\n# Visible\n"
        try write(project, to: root.appendingPathComponent("01-projects/visible/visible.md"))
        let excluded = [
            "01-projects/_private/secret.md", "01-projects/generated-board.md",
            "01-projects/repository/hidden.md", "04-archive/retired.md",
        ]
        for path in excluded {
            try write("---\ntype: project\n---\n# Private vault text\n", to: root.appendingPathComponent(path))
        }
        try write("[core]\n", to: root.appendingPathComponent("01-projects/repository/.git/config"))
        let context = try await selectedVault(root)
        let (result, block) = try await run(context)
        let content = try XCTUnwrap(block["content"] as? String)
        let payload = try XCTUnwrap(parseJSONObject(Data(content.utf8)))
        let projects = try XCTUnwrap(payload["projects"] as? [[String: Any]])
        XCTAssertEqual(projects.compactMap { $0["slug"] as? String }, ["visible"])
        XCTAssertFalse(content.contains("Private vault text"))
        XCTAssertFalse(content.contains("hidden.md"))
        XCTAssertEqual(result.call.citations, [ToolCitation(kind: .path, value: "01-projects/visible/visible.md")])
        for input in [#"{"slug":"visible"}"#, #"{"limit":1}"#, "[]"] {
            let (invalid, invalidBlock) = try await run(context, input: input)
            XCTAssertTrue(invalid.call.isError, input)
            XCTAssertEqual(invalidBlock["is_error"] as? Bool, true)
            XCTAssertTrue(invalid.call.citations.isEmpty)
        }
    }

    func testInventoryDoesNotCiteAHubThatDisappearedAfterRefresh() async throws {
        let root = try makeTemporaryVault(self)
        let path = "01-projects/visible/visible.md"
        try write("---\ntype: project\n---\n# Visible\n", to: root.appendingPathComponent(path))
        let context = try await selectedVault(root)
        try FileManager.default.removeItem(at: root.appendingPathComponent(path))

        let (result, block) = try await run(context)
        let inventory = try payload(block)
        XCTAssertEqual(inventory["state"] as? String, "partial")
        XCTAssertEqual((inventory["projects"] as? [Any])?.count, 0)
        XCTAssertTrue(result.call.citations.isEmpty)
        let project = await AssistantToolRunner(context: context).run(
            AgentToolUse(id: "missing", name: "get_project", input: Data(#"{"slug":"visible"}"#.utf8)))
        XCTAssertTrue(project.call.isError)
        XCTAssertTrue(project.call.citations.isEmpty)
    }

    func testProjectPreservesNativeTicketsWhenBoardPlacementIsUnavailable() async throws {
        let root = try makeTemporaryVault(self)
        try write("---\ntype: project\n---\n# Atlas\n", to: root.appendingPathComponent("01-projects/atlas/atlas.md"))
        let directory = try makeTemporaryVault(self)
        let shell = AppModel(dependencies: .test())
        let projects = ProjectsStore(
            registry: AssociationRegistry(directory: WorkspaceDirectory(url: directory)),
            luuna: nil, vaultRoot: root)
        await projects.refresh()
        projects.select("atlas")
        XCTAssertNil(projects.bindLuuna(origin: .standard, projectID: "native-project"))
        let work = LuunaWorkStore(reader: TicketOnlyReader())
        work.connect(origin: .standard, token: "test-token", projectID: "native-project")
        await work.refresh()
        XCTAssertEqual(work.tickets.state, .populated)
        XCTAssertFalse(work.board.state.isSuccess)
        let context = WorkspaceAssistantContext(
            vaultRoot: { root }, openLoops: shell.openLoops, projects: projects, luunaWork: work,
            calendarStore: FakeCalendarStore(),
            ledger: RestartLedger(url: directory.appendingPathComponent("restart-ledger.jsonl")))

        let result = await AssistantToolRunner(context: context).run(
            AgentToolUse(id: "project", name: "get_project", input: Data(#"{"slug":"atlas"}"#.utf8)))
        XCTAssertFalse(result.call.isError, result.call.errorMessage ?? "")
        let block = try XCTUnwrap(parseJSONObject(result.block))
        let content = try XCTUnwrap(block["content"] as? String)
        let project = try XCTUnwrap(parseJSONObject(Data(content.utf8)))
        let tickets = try XCTUnwrap(project["native_tickets"] as? [[String: Any]])
        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0]["id"] as? String, "native-1")
        XCTAssertEqual(tickets[0]["status"] as? String, "open")
        XCTAssertNil(tickets[0]["board_column"])
        XCTAssertNil(project["native_tickets_unavailable"])
        XCTAssertTrue(result.call.citations.contains(.init(kind: .record, value: "native-1")))
    }

    func testRestartPromptRequestsOnlyAStructuredJSONObject() {
        let request = AssistantPrompt.restartRequest(project: "alpha")
        XCTAssertTrue(request.contains("exactly one JSON object"))
        XCTAssertTrue(request.contains("decision, next_action, notes, sources_read"))
        XCTAssertTrue(request.contains("Do not include prose"))
    }

    func testInventoryBoundsTheNumberOfProjectsAndMarksTruncation() async throws {
        let root = try makeTemporaryVault(self)
        for index in 0...(AssistantTool.projectLimit) {
            let name = String(format: "hub-%03d", index)
            try write(
                "---\ntype: project\n---\n# \(name)\n",
                to: root.appendingPathComponent("01-projects/\(name)/\(name).md"))
        }
        let context = try await selectedVault(root)
        let (result, block) = try await run(context)
        let payload = try XCTUnwrap(parseJSONObject(Data((block["content"] as? String ?? "").utf8)))
        XCTAssertEqual(payload["state"] as? String, "populated")
        XCTAssertEqual((payload["projects"] as? [Any])?.count, AssistantTool.projectLimit)
        XCTAssertEqual(result.call.citations.count, AssistantTool.projectLimit)
        XCTAssertEqual(payload["truncated"] as? Bool, true)
    }
}
