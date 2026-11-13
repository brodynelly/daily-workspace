import XCTest

@testable import DailyCore

final class LuunaBoardModelsTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testBoardUsesNativeColumnsEvenWhenAWorkflowCompleted() throws {
        let board = try decode(LuunaBoard.self, Self.board)
        XCTAssertEqual(board.note, "Cards are read-only; dragging cannot bypass a validation gate.")
        XCTAssertEqual(board.columns.map(\.column.id), ["backlog", "testing_prerequisite", "plan", "future_qa"])
        XCTAssertEqual(board.columns[1].cards, [], "Empty lanes retain their native order")

        let backlog = try XCTUnwrap(board.cards(forProjectID: "daily-workspace").first)
        XCTAssertEqual(backlog.column.rawValue, "backlog")
        XCTAssertEqual(backlog.ticketID, "ticket-backlog")
        XCTAssertNil(backlog.state)
        XCTAssertNil(backlog.runID)
        let completedRun = try XCTUnwrap(board.columns[2].cards.first)
        XCTAssertEqual(completedRun.ticketID, "ticket-planned")
        XCTAssertEqual(completedRun.runID, "workflow-completed")
        XCTAssertEqual(completedRun.state?.rawValue, "completed")
        XCTAssertEqual(completedRun.column.rawValue, "plan", "Run completion must not become a closed ticket")
        XCTAssertEqual(completedRun.planRevision, 4)
        XCTAssertEqual(
            board.cards(forProjectID: "daily-workspace").map(\.ticketID), ["ticket-backlog", "ticket-planned"])
        XCTAssertEqual(board.cards(forProjectID: "other-project").map(\.ticketID), ["ticket-other", "ticket-future"])
        XCTAssertEqual(board.cards(forProjectID: "unbound"), [])

        let unknown = try XCTUnwrap(board.columns.last?.cards.first)
        XCTAssertEqual(unknown.column.rawValue, "future_qa")
        XCTAssertEqual(unknown.state?.rawValue, "accelerating")
        XCTAssertEqual(unknown.kind.rawValue, "ticket")
        XCTAssertEqual(unknown.rawFields["future_status"], .object(["canary": .bool(true)]))
        let roundTrip = try JSONDecoder().decode(LuunaBoard.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(roundTrip, board, "Native fields remain available after serialization")
    }

    func testEmptyBoardAndEmptyTicketListAreValid() throws {
        let board = try decode(
            LuunaBoard.self, #"{"columns":[{"column":{"id":"backlog","title":"Backlog"},"cards":[]}],"note":null}"#)
        XCTAssertEqual(board.columns.count, 1)
        XCTAssertEqual(board.cards(forProjectID: "daily-workspace"), [])
        XCTAssertEqual(try decode(LuunaBoard.self, #"{"columns":[]}"#).columns, [])
        XCTAssertEqual(try decode([LuunaTicketRecord].self, "[]"), [])
    }

    func testTicketListAndDetailKeepNativeIDsAndUnknownFields() throws {
        let tickets = try decode([LuunaTicketRecord].self, Self.tickets)
        XCTAssertEqual(tickets.map(\.id), ["ticket-backlog", "ticket-other"])
        XCTAssertEqual(tickets.filter { $0.projectID == "daily-workspace" }.map(\.id), ["ticket-backlog"])
        XCTAssertNil(tickets[0].status, "No status is inferred from revision or unrelated run state")
        XCTAssertEqual(tickets[0].repositoryIDs, ["app"])
        XCTAssertEqual(tickets[0].acceptanceCriteria, ["Approved by owner"])
        XCTAssertEqual(tickets[0].createdAt, "2026-11-13T09:34:26.150Z")
        XCTAssertEqual(tickets[1].status?.rawValue, "needs_research", "Unknown status remains native")

        let detail = try decode(LuunaTicketRecord.self, Self.ticketDetail)
        XCTAssertEqual(detail.id, "ticket-backlog")
        XCTAssertEqual(detail.projectID, "daily-workspace")
        XCTAssertEqual(detail.usage?["workflows"]?.intValue, 4)
        XCTAssertEqual(detail.usage?["cost_unreported"], .bool(false))
        XCTAssertEqual(detail.rawFields["future_tags"], .array([.string("important")]))
        XCTAssertEqual(try JSONDecoder().decode(LuunaTicketRecord.self, from: JSONEncoder().encode(detail)), detail)
    }

    func testHomePreservesProjectCountsRepositoriesAndRuntimeBlockers() throws {
        let home = try decode(LuunaHome.self, Self.home)
        XCTAssertEqual(home.projects.map(\.id), ["luuna", "daily-workspace"])
        XCTAssertEqual(home.project(id: "daily-workspace")?.tickets, 29)
        XCTAssertEqual(home.project(id: "daily-workspace")?.activeWorkflows, 1)
        XCTAssertNil(home.project(id: "missing"))
        let repository = try XCTUnwrap(home.project(id: "daily-workspace")?.repositories.first)
        XCTAssertEqual(repository.repositoryID, "app")
        XCTAssertEqual(repository.baseline?["status"], .string("passed"))
        XCTAssertEqual(repository.baseline?["run_id"], .string("baseline-1"))
        XCTAssertNil(repository.prerequisite)
        XCTAssertEqual(home.blockers.first?.state?.rawValue, "failed")
        XCTAssertEqual(home.blockers.first?.ticketID, "ticket-backlog")
        XCTAssertEqual(home.rawFields["next_projection"], .string("pending"))
        XCTAssertEqual(try JSONDecoder().decode(LuunaHome.self, from: JSONEncoder().encode(home)), home)
    }

    func testMalformedRecordsFailExplicitlyInsteadOfDisappearing() {
        let malformed: [(String, String)] = [
            (#"{"columns":[{"column":{"title":"Backlog"},"cards":[]}]}"#, "id"),
            (
                #"{"columns":[{"column":{"id":"backlog","title":"Backlog"},"cards":[{"column":"backlog","kind":"ticket","project_id":"p","title":"No ID"}]}]}"#,
                "ticket_id"
            ),
            (#"{"columns":[{"column":{"id":"backlog","title":"Backlog"},"cards":[42]}]}"#, "cards"),
        ]
        for (json, field) in malformed {
            XCTAssertThrowsError(try decode(LuunaBoard.self, json), field) { error in
                XCTAssertTrue(error is DecodingError, "\(error)")
            }
        }
        XCTAssertThrowsError(
            try decode(
                LuunaTicketRecord.self, #"{"id":"ticket-1","project_id":"p","revision":"one","title":"Bad revision"}"#)
        ) {
            guard case DecodingError.typeMismatch(_, let context) = $0 else {
                return XCTFail("Expected type mismatch: \($0)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "revision")
        }
        XCTAssertThrowsError(
            try decode(LuunaHome.self, #"{"projects":[{"name":"Missing ID","repositories":[]}],"blockers":[]}"#))
    }

    private static let board = """
        {"columns":[
          {"column":{"id":"backlog","title":"Backlog","description":"Tickets without a plan revision."},
           "cards":[{"column":"backlog","kind":"ticket","project_id":"daily-workspace","title":"T02 Dock icon", "ticket_id":"ticket-backlog","ticket_revision":1},
                    {"column":"backlog","kind":"ticket","project_id":"other-project","title":"Other ticket","ticket_id":"ticket-other","ticket_revision":3}]},
          {"column":{"id":"testing_prerequisite","title":"Testing prerequisite","description":"Repositories with unavailable checks."},"cards":[]},
          {"column":{"id":"plan","title":"Discovery / plan","description":"Settled workflows whose next step is a plan revision."},
           "cards":[{"column":"plan","kind":"ticket","project_id":"daily-workspace","title":"T01 Build shell","ticket_id":"ticket-planned","ticket_revision":2,"run_id":"workflow-completed","state":"completed","plan_revision":4}]},
          {"column":{"id":"future_qa","title":"Future QA","description":"Native future workflow."},
           "cards":[{"column":"future_qa","kind":"ticket","project_id":"other-project","title":"Future ticket","ticket_id":"ticket-future","ticket_revision":1,"state":"accelerating","future_status":{"canary":true}}]}
         ],"note":"Cards are read-only; dragging cannot bypass a validation gate.","future_layout":{"version":2}}
        """

    private static let tickets = """
        [{"schema_version":"0.1","id":"ticket-backlog","project_id":"daily-workspace","revision":1,"source":"missions","title":"T02 Dock icon","intent":"Choose an icon","acceptance_criteria":["Approved by owner"],"repository_ids":["app"],"created_at":"2026-11-13T09:34:26.150Z","updated_at":"2026-11-13T09:34:26.150Z"},
         {"schema_version":"0.1","id":"ticket-other","project_id":"other-project","revision":3,"source":"missions","title":"Other ticket","intent":"Other work","acceptance_criteria":[],"repository_ids":[],"created_at":"2026-11-13T09:34:27Z","updated_at":"2026-11-13T09:34:27Z","status":"needs_research"}]
        """

    private static let ticketDetail = """
        {"schema_version":"0.1","id":"ticket-backlog","project_id":"daily-workspace","revision":1,"source":"missions","title":"T02 Dock icon","intent":"Choose an icon","acceptance_criteria":["Approved by owner"],"repository_ids":["app"],"created_at":"2026-11-13T09:34:26.150Z","updated_at":"2026-11-13T09:34:26.150Z","usage":{"workflows":4,"attempts":2,"elapsed_seconds":112,"cost_usd_micros":50004924,"cost_unreported":false,"repairs":0},"future_tags":["important"]}
        """

    private static let home = """
        {"projects":[{"id":"luuna","name":"Luuna","revision":0,"manifest_hash":null,"repositories":[{"repository_id":"app","local_path":"/src/luuna","baseline":null,"prerequisite":null}],"tickets":15,"active_workflows":0},
         {"id":"daily-workspace","name":"daily-workspace","revision":2,"manifest_hash":"sha256:e22f","repositories":[{"repository_id":"app","local_path":"/src/daily-workspace","baseline":{"run_id":"baseline-1","status":"passed","manifest_revision":2,"commit":"d6b70d7"},"prerequisite":null}],"tickets":29,"active_workflows":1}],
         "blockers":[{"kind":"workflow","project_id":"daily-workspace","title":"T00 Approve Increment 4","detail":"workflow workflow-1 (plan r4) is failed","run_id":"workflow-1","state":"failed","ticket_id":"ticket-backlog"}],"next_projection":"pending"}
        """
}
