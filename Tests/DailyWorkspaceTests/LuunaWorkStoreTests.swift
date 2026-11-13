import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

private final class WorkReaderFake: LuunaWorkReading, @unchecked Sendable {
    private let lock = NSLock()
    private var boardGate: LuunaGate?
    private var globalHomeGate: LuunaGate?
    private var boardResponse = Data(#"{"columns":[]}"#.utf8)
    private var ticketResponse = Data("[]".utf8)
    private var detailResponse = Data(#"{"id":"t","project_id":"p","revision":1,"title":"Open","status":"open"}"#.utf8)
    private var homeResponse = Data(#"{"projects":[],"blockers":[]}"#.utf8)
    private var globalHomeResponse = Data(#"{"projects":[],"blockers":[]}"#.utf8)
    private var runsResponse = Data("[]".utf8)
    private var runResponse = Data(#"{"id":"r","project_id":"p","state":"completed"}"#.utf8)
    private var runsGate: LuunaGate?

    private var failure: LuunaReadFailure?
    private var seen: [(String, LuunaConnection)] = []

    var calls: [(String, LuunaConnection)] { lock.withLock { seen } }
    func setBoard(_ data: Data) { lock.withLock { boardResponse = data } }
    func setTickets(_ data: Data) { lock.withLock { ticketResponse = data } }
    func setGlobalHome(_ data: Data) { lock.withLock { globalHomeResponse = data } }
    func setRuns(_ data: Data) { lock.withLock { runsResponse = data } }
    func setRun(_ data: Data) { lock.withLock { runResponse = data } }
    func holdRuns() -> LuunaGate {
        let gate = LuunaGate()
        lock.withLock { runsGate = gate }
        return gate
    }

    func setFailure(_ value: LuunaReadFailure?) { lock.withLock { failure = value } }
    func holdBoard() -> LuunaGate {
        let gate = LuunaGate()
        lock.withLock { boardGate = gate }
        return gate
    }
    func holdGlobalHome() -> LuunaGate {
        let gate = LuunaGate()
        lock.withLock { globalHomeGate = gate }
        return gate
    }

    private struct Response {
        let data: Data
        let failure: LuunaReadFailure?
        let gate: LuunaGate?
    }

    private func response(_ command: String, _ connection: LuunaConnection) -> Response {
        lock.withLock {
            seen.append((command, connection))
            let data: Data
            switch command {
            case "board": data = boardResponse
            case "tickets": data = ticketResponse
            case "detail": data = detailResponse
            case "globalHome": data = globalHomeResponse
            case "runs": data = runsResponse
            case "run": data = runResponse
            default: data = homeResponse
            }
            return Response(
                data: data, failure: failure,
                gate: command == "board"
                    ? boardGate
                    : command == "globalHome" ? globalHomeGate : command == "runs" ? runsGate : nil)
        }
    }
    private func fetch<Value: Decodable>(_ command: String, _ connection: LuunaConnection) async throws -> Value {
        let response = response(command, connection)
        if let gate = response.gate { await gate.wait() }
        if let failure = response.failure { throw failure }
        return try JSONDecoder().decode(Value.self, from: response.data)
    }
    func board(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaBoard {
        try await fetch("board", connection)
    }
    func tickets(_ projectID: String, _ connection: LuunaConnection) async throws -> [LuunaTicketRecord] {
        try await fetch("tickets", connection)
    }
    func showTicket(_ ticketID: String, _ connection: LuunaConnection) async throws -> LuunaTicketRecord {
        try await fetch("detail", connection)
    }
    func home(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaHome {
        try await fetch("home", connection)
    }
    func homeAll(_ connection: LuunaConnection) async throws -> LuunaHome {
        try await fetch("globalHome", connection)
    }
    func runs(_ projectID: String, _ connection: LuunaConnection) async throws -> [LuunaRunRecord] {
        try await fetch("runs", connection)
    }
    func run(_ runID: String, _ connection: LuunaConnection) async throws -> LuunaRunRecord {
        try await fetch("run", connection)
    }
}

@MainActor
final class LuunaWorkStoreTests: XCTestCase {
    private static let nativeBoard = Data(
        #"{"columns":[{"column":{"id":"future_qa","title":"Future QA"},"cards":[{"column":"future_qa","kind":"ticket","project_id":"p","title":"Still open","ticket_id":"t","run_id":"completed-run","state":"completed"}]}]}"#
            .utf8)
    private static let ticket = Data(
        #"[{"id":"t","project_id":"p","revision":1,"title":"Still open","status":"open"}]"#.utf8)

    func testNativeStatesRetainLastGoodAndClearOnConnectionSwitch() async {
        let reader = WorkReaderFake()
        reader.setBoard(Self.nativeBoard)
        reader.setTickets(Self.ticket)
        let instant = Date(timeIntervalSince1970: 1234)
        let store = LuunaWorkStore(reader: reader, now: { instant })
        store.connect(origin: .standard, token: "first", projectID: "p")
        await store.refresh()
        XCTAssertEqual(store.board.state, .populated)
        XCTAssertEqual(store.board.value?.columns.first?.column.id, "future_qa")
        XCTAssertEqual(store.board.value?.columns.first?.cards.first?.state?.rawValue, "completed")
        XCTAssertEqual(store.tickets.value?.first?.status?.rawValue, "open")
        XCTAssertEqual(store.home.state, .empty)
        store.selectTicket("t")
        await store.refreshSelectedTicket()
        XCTAssertEqual(store.selectedTicket.value?.status?.rawValue, "open")
        reader.setFailure(.unavailable(.timedOut))
        await store.refresh()
        XCTAssertEqual(store.board.state, .unavailable(.timedOut))
        XCTAssertEqual(store.board.lastSuccessAt, instant)
        XCTAssertEqual(store.board.value?.columns.first?.column.id, "future_qa")
        store.connect(origin: .standard, token: "second", projectID: "other")
        XCTAssertNil(store.board.value)
        XCTAssertNil(store.tickets.value)
        XCTAssertNil(store.home.value)
        XCTAssertNil(store.selectedTicket.value)
        XCTAssertNil(store.selectedTicketID)
        XCTAssertNil(store.board.lastSuccessAt)
        await store.refresh()
        XCTAssertEqual(reader.calls.last?.1.token, "second")
        XCTAssertNil(store.board.value)
    }

    func testStaleReadCannotPublishAcrossProjectSwitch() async throws {
        let reader = WorkReaderFake()
        reader.setBoard(Self.nativeBoard)
        let gate = reader.holdBoard()
        let store = LuunaWorkStore(reader: reader)
        store.connect(origin: .standard, token: "first", projectID: "p")
        let oldRead = Task { await store.refresh() }
        try await gate.waitForArrival()
        store.connect(origin: .standard, token: "new", projectID: "other")
        gate.open()
        await oldRead.value
        XCTAssertNil(store.board.value)
        XCTAssertNil(store.tickets.value)
        XCTAssertNil(store.home.value)
        XCTAssertEqual(store.board.state, .unavailable(.notChecked))
    }

    func testForeignRecordsCannotLeakIntoSelectedProject() async {
        let reader = WorkReaderFake()
        reader.setBoard(Self.nativeBoard)
        reader.setTickets(Self.ticket)
        let store = LuunaWorkStore(reader: reader)
        store.connect(origin: .standard, token: "first", projectID: "other")
        await store.refresh()
        XCTAssertEqual(store.board.state, .partial)
        XCTAssertNil(store.board.value)
        XCTAssertEqual(store.tickets.state, .partial)
        XCTAssertNil(store.tickets.value)
        store.selectTicket("t")
        await store.refreshSelectedTicket()
        XCTAssertEqual(store.selectedTicket.state, .partial)
        XCTAssertNil(store.selectedTicket.value)
    }

    func testGlobalHomeReadsEveryProjectWithoutSelectionAndPreservesNativeBlockers() async {
        let reader = WorkReaderFake()
        reader.setGlobalHome(
            Data(
                #"{"projects":[{"id":"p","name":"One","repositories":[]},{"id":"other","name":"Two","repositories":[]}],"blockers":[{"kind":"new-blocker","project_id":"other","state":"new-state","title":"Runtime issue"}]}"#
                    .utf8))
        let store = LuunaWorkStore(reader: reader)
        store.connect(origin: .standard, token: "first", projectID: nil)
        XCTAssertEqual(store.globalHome.state, .unavailable(.notChecked))
        await store.refreshGlobalHome()
        XCTAssertEqual(reader.calls.map(\.0), ["globalHome"])
        XCTAssertEqual(store.globalHome.state, .populated)
        XCTAssertEqual(store.globalHome.value?.projects.map(\.id), ["p", "other"])
        XCTAssertEqual(store.globalHome.value?.blockers.first?.kind.rawValue, "new-blocker")
        XCTAssertEqual(store.globalHome.value?.blockers.first?.state?.rawValue, "new-state")

        store.connect(origin: .standard, token: "first", projectID: "p")
        XCTAssertEqual(store.globalHome.value?.projects.count, 2)
        XCTAssertEqual(store.globalHome.state, .populated)
    }

    func testGlobalHomeDistinguishesUnknownUnauthorizedAndEmpty() async {
        let reader = WorkReaderFake()
        let store = LuunaWorkStore(reader: reader)
        XCTAssertEqual(store.globalHome.state, .unavailable(.notChecked))
        await store.refreshGlobalHome()
        XCTAssertEqual(store.globalHome.state, .unauthorized)
        XCTAssertNil(store.globalHome.value)
        XCTAssertTrue(reader.calls.isEmpty)

        store.connect(origin: .standard, token: "first", projectID: nil)
        XCTAssertEqual(store.globalHome.state, .unavailable(.notChecked))
        await store.refreshGlobalHome()
        XCTAssertEqual(store.globalHome.state, .empty)
        XCTAssertEqual(store.globalHome.value?.projects.count, 0)
        reader.setFailure(.unauthorized)
        await store.refreshGlobalHome()
        XCTAssertEqual(store.globalHome.state, .unauthorized)
        XCTAssertEqual(store.globalHome.value?.projects.count, 0)
        XCTAssertTrue(store.globalHome.isShowingRetainedValue)
    }

    func testGlobalHomeDiscardsInFlightResponseAcrossConnectionSwitch() async throws {
        let reader = WorkReaderFake()
        reader.setGlobalHome(Data(#"{"projects":[{"id":"old","name":"Old","repositories":[]}],"blockers":[]}"#.utf8))
        let gate = reader.holdGlobalHome()
        let store = LuunaWorkStore(reader: reader)
        store.connect(origin: .standard, token: "first", projectID: nil)
        let oldRead = Task { await store.refreshGlobalHome() }
        try await gate.waitForArrival()
        store.connect(origin: .standard, token: "second", projectID: nil)
        XCTAssertNil(store.globalHome.value)
        XCTAssertEqual(store.globalHome.state, .unavailable(.notChecked))
        gate.open()
        await oldRead.value
        XCTAssertNil(store.globalHome.value)
        XCTAssertEqual(store.globalHome.state, .unavailable(.notChecked))

        reader.setGlobalHome(Data(#"{"projects":[{"id":"new","name":"New","repositories":[]}],"blockers":[]}"#.utf8))
        await store.refreshGlobalHome()
        XCTAssertEqual(store.globalHome.value?.projects.map(\.id), ["new"])
        XCTAssertEqual(store.globalHome.state, .populated)
        XCTAssertEqual(reader.calls.map(\.1.token), ["first", "second"])

        let otherOrigin = try LuunaOrigin(validating: "http://127.0.0.1:5151")
        store.connect(origin: otherOrigin, token: "second", projectID: nil)
        XCTAssertNil(store.globalHome.value)
        XCTAssertEqual(store.globalHome.state, .unavailable(.notChecked))
    }
    func testRunStatesRemainSeparateFromTicketAndRejectForeignIdentity() async {
        let reader = WorkReaderFake()
        reader.setRuns(Data(#"[{"id":"r","project_id":"p","state":"completed","metadata":{"ticket_id":"t"}}]"#.utf8))
        reader.setTickets(Self.ticket)
        let store = LuunaWorkStore(reader: reader)
        store.connect(origin: .standard, token: "first", projectID: "p")
        await store.refresh()
        XCTAssertEqual(store.runs.value?.first?.state.rawValue, "completed")
        XCTAssertEqual(store.tickets.value?.first?.status?.rawValue, "open")
        store.selectRun("r")
        await store.refreshSelectedRun()
        XCTAssertEqual(store.selectedRun.value?.id, "r")

        reader.setRun(Data(#"{"id":"another","project_id":"p","state":"running"}"#.utf8))
        await store.refreshSelectedRun()
        XCTAssertEqual(store.selectedRun.state, .partial)
        XCTAssertEqual(store.selectedRun.value?.id, "r")
        reader.setRuns(Data(#"[{"id":"foreign","project_id":"elsewhere","state":"queued"}]"#.utf8))
        await store.refresh()
        XCTAssertEqual(store.runs.state, .partial)
        XCTAssertEqual(store.runs.value?.first?.id, "r")
        store.connect(origin: .standard, token: "second", projectID: "p")
        XCTAssertNil(store.runs.value)
        XCTAssertNil(store.selectedRun.value)
    }

    func testRunReadsDistinguishNoTokenEmptyAndUnauthorized() async {
        let reader = WorkReaderFake()
        let store = LuunaWorkStore(reader: reader)
        await store.refresh()
        XCTAssertEqual(store.runs.state, .unauthorized)
        XCTAssertTrue(reader.calls.isEmpty)
        store.connect(origin: .standard, token: "first", projectID: "p")
        await store.refresh()
        XCTAssertEqual(store.runs.state, .empty)
        reader.setFailure(.unauthorized)
        await store.refresh()
        XCTAssertEqual(store.runs.state, .unauthorized)
        XCTAssertTrue(store.runs.isShowingRetainedValue)
    }

    func testRunListRejectsOldResponseAfterBindingSwitch() async throws {
        let reader = WorkReaderFake()
        reader.setRuns(Data(#"[{"id":"old","project_id":"p","state":"running"}]"#.utf8))
        let gate = reader.holdRuns()
        let store = LuunaWorkStore(reader: reader)
        store.connect(origin: .standard, token: "first", projectID: "p")
        let oldRead = Task { await store.refresh() }
        try await gate.waitForArrival()
        store.connect(origin: .standard, token: "second", projectID: "other")
        gate.open()
        await oldRead.value
        XCTAssertNil(store.runs.value)
        XCTAssertEqual(store.runs.state, .unavailable(.notChecked))
    }
}
