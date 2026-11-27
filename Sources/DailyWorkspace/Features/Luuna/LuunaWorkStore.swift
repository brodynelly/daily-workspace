import DailyCore
import Foundation

/// Read-only native work and Home projections for a Luuna connection.
protocol LuunaWorkReading: Sendable {
    func board(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaBoard
    func tickets(_ projectID: String, _ connection: LuunaConnection) async throws -> [LuunaTicketRecord]
    func showTicket(_ ticketID: String, _ connection: LuunaConnection) async throws -> LuunaTicketRecord
    func home(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaHome
    func homeAll(_ connection: LuunaConnection) async throws -> LuunaHome
    func runs(_ projectID: String, _ connection: LuunaConnection) async throws -> [LuunaRunRecord]
    func run(_ runID: String, _ connection: LuunaConnection) async throws -> LuunaRunRecord

}

extension LuunaCLIReader: LuunaWorkReading {}

@MainActor
final class LuunaWorkStore: ObservableObject {
    @Published private(set) var board = LuunaObservation<LuunaBoard>()
    @Published private(set) var tickets = LuunaObservation<[LuunaTicketRecord]>()
    @Published private(set) var home = LuunaObservation<LuunaHome>()
    @Published private(set) var globalHome = LuunaObservation<LuunaHome>()
    @Published private(set) var selectedTicket = LuunaObservation<LuunaTicketRecord>()
    @Published private(set) var selectedTicketID: String?
    @Published private(set) var runs = LuunaObservation<[LuunaRunRecord]>()
    @Published private(set) var selectedRun = LuunaObservation<LuunaRunRecord>()
    @Published private(set) var selectedRunID: String?
    let follower: LuunaRunFollower

    @Published private(set) var isRefreshing = false

    private let reader: any LuunaWorkReading
    private let now: () -> Date
    private var connection: LuunaConnection?
    private var projectID: String?
    private var generation = 0
    private var connectionGeneration = 0
    private var selectionGeneration = 0
    private var runSelectionGeneration = 0

    private var refreshingGeneration: Int?

    /// Identity of the project currently owning the board and ticket observations.
    var observedProjectBinding: LuunaProjectBinding? {
        guard let connection, let projectID else { return nil }
        return LuunaProjectBinding(origin: connection.origin, projectID: projectID)
    }

    init(
        reader: any LuunaWorkReading = LuunaCLIReader(), follower: LuunaRunFollower? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.reader = reader
        self.follower = follower ?? LuunaRunFollower()
        self.now = now
    }

    /// Project changes reset project-scoped values; connection changes also reset the all-project Home.
    func connect(origin: LuunaOrigin, token: String?, projectID: String?) {
        let token = token.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let next = token.map { LuunaConnection(origin: origin, token: $0) }
        guard next != connection || projectID != self.projectID else { return }
        let connectionChanged = next != connection
        connection = next
        self.projectID = projectID
        generation += 1
        selectionGeneration += 1
        runSelectionGeneration += 1
        follower.stop()

        refreshingGeneration = nil
        isRefreshing = false
        board = LuunaObservation()
        tickets = LuunaObservation()
        home = LuunaObservation()
        runs = LuunaObservation()
        selectedRunID = nil
        selectedRun = LuunaObservation()
        if connectionChanged {
            connectionGeneration += 1
            globalHome = LuunaObservation()
        }
        selectedTicketID = nil
        selectedTicket = LuunaObservation()
    }

    func selectTicket(_ ticketID: String?) {
        guard ticketID != selectedTicketID else { return }
        selectedTicketID = ticketID
        selectionGeneration += 1
        selectedTicket = LuunaObservation()
    }
    func selectRun(_ runID: String?) {
        guard runID != selectedRunID else { return }
        selectedRunID = runID
        runSelectionGeneration += 1
        follower.stop()
        selectedRun = LuunaObservation()
    }

    func followSelectedRun() {
        guard let connection, let projectID, let selectedRunID else { return }
        follower.start(runID: selectedRunID, projectID: projectID, connection: connection)
    }

    func refresh() async {
        let generation = generation
        guard refreshingGeneration != generation else { return }
        guard let connection, let projectID else {
            let state: LuunaReadState = connection == nil ? .unauthorized : .unavailable(.notChecked)
            board.recordFailure(state, at: now())
            tickets.recordFailure(state, at: now())
            home.recordFailure(state, at: now())
            runs.recordFailure(state, at: now())

            return
        }
        refreshingGeneration = generation
        isRefreshing = true
        defer {
            if generation == self.generation {
                refreshingGeneration = nil
                isRefreshing = false
            }
        }
        async let boardResult = read { try await $0.board(projectID, connection) }
        async let ticketResult = read { try await $0.tickets(projectID, connection) }
        async let homeResult = read { try await $0.home(projectID, connection) }
        async let runResult = read { try await $0.runs(projectID, connection) }

        let (newBoard, newTickets, newHome, newRuns) = await (boardResult, ticketResult, homeResult, runResult)
        guard generation == self.generation, !Task.isCancelled else { return }
        if let newBoard {
            record(
                newBoard.flatMap { boardForProject($0, projectID) }, in: \.board,
                state: { $0.cards(forProjectID: projectID).isEmpty ? .empty : .populated })
        }
        if let newTickets {
            record(
                newTickets.flatMap { list in
                    list.allSatisfy { $0.projectID == projectID } ? .success(list) : .failure(.undecodable)
                }, in: \.tickets, state: { $0.isEmpty ? .empty : .populated })
        }
        if let newHome {
            record(newHome, in: \.home, state: { $0.project(id: projectID) == nil ? .empty : .populated })
        }
        if let newRuns {
            record(
                newRuns.flatMap { list in
                    list.allSatisfy { $0.projectID == projectID } ? .success(list) : .failure(.undecodable)
                }, in: \.runs, state: { $0.isEmpty ? .empty : .populated })
        }

    }

    /// Reads all-project native Home without requiring a selected project.
    func refreshGlobalHome() async {
        let generation = connectionGeneration
        guard let connection else {
            globalHome.recordFailure(.unauthorized, at: now())
            return
        }
        let result: Result<LuunaHome, LuunaReadFailure>? = await read {
            try await $0.homeAll(connection)
        }
        guard generation == connectionGeneration, !Task.isCancelled, let result else { return }
        record(
            result, in: \.globalHome,
            state: {
                $0.projects.isEmpty && $0.blockers.isEmpty ? .empty : .populated
            })
    }

    func refreshSelectedTicket() async {
        let generation = generation
        let selection = selectionGeneration
        guard let connection, let projectID, let ticketID = selectedTicketID else { return }
        let result: Result<LuunaTicketRecord, LuunaReadFailure>? = await read {
            try await $0.showTicket(ticketID, connection)
        }
        guard generation == self.generation, selection == selectionGeneration, !Task.isCancelled,
            let result
        else { return }
        record(
            result.flatMap { detail in
                detail.projectID == projectID && detail.id == ticketID ? .success(detail) : .failure(.undecodable)
            }, in: \.selectedTicket)
    }
    func refreshSelectedRun() async {
        let generation = generation
        let selection = runSelectionGeneration
        guard let connection, let projectID, let runID = selectedRunID else { return }
        let result: Result<LuunaRunRecord, LuunaReadFailure>? = await read {
            try await $0.run(runID, connection)
        }
        guard generation == self.generation, selection == runSelectionGeneration, !Task.isCancelled,
            let result
        else { return }
        record(
            result.flatMap { detail in
                detail.projectID == projectID && detail.id == runID ? .success(detail) : .failure(.undecodable)
            }, in: \.selectedRun)
    }

    private func read<Value: Sendable>(_ operation: (any LuunaWorkReading) async throws -> Value) async
        -> Result<Value, LuunaReadFailure>?
    {
        do {
            let value = try await operation(reader)
            return Task.isCancelled ? nil : .success(value)
        } catch is CancellationError {
            return nil
        } catch let failure as LuunaReadFailure {
            return Task.isCancelled ? nil : .failure(failure)
        } catch {
            return Task.isCancelled ? nil : .failure(.unavailable(.cannotConnect))
        }
    }

    private func record<Value>(
        _ result: Result<Value, LuunaReadFailure>,
        in keyPath: ReferenceWritableKeyPath<LuunaWorkStore, LuunaObservation<Value>>,
        state: (Value) -> LuunaReadState = { _ in .populated }
    ) {
        switch result {
        case .success(let value): self[keyPath: keyPath].recordSuccess(value, state: state(value), at: now())
        case .failure(let failure): self[keyPath: keyPath].recordFailure(failure.state, at: now())
        }
    }

    /// A board command is project-scoped, but reject foreign cards rather than display another project.
    private func boardForProject(_ value: LuunaBoard, _ projectID: String) -> Result<LuunaBoard, LuunaReadFailure> {
        value.columns.flatMap(\.cards).allSatisfy { $0.projectID == projectID }
            ? .success(value) : .failure(.undecodable)
    }
}
