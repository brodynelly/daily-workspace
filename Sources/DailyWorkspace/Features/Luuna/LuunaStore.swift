import DailyCore
import Foundation

/// Read-only observations of one Luuna runtime, for one connection session at a time.
///
/// A session is an origin, a token and an optional selected project. Changing any of them starts a new session
/// (`generation` goes up) and every response from an older session is discarded, so results from another origin,
/// token or project never populate the current one. Within a session each observation keeps its last good value
/// and its time across failures. There is no polling loop: the caller decides when to `refresh()`. The store never
/// sends anything but the GETs of `LuunaRuntimeReading`.
@MainActor
final class LuunaStore: ObservableObject {
    @Published private(set) var origin: LuunaOrigin
    /// Whether a token was supplied. The token itself is not published.
    @Published private(set) var hasToken: Bool
    @Published private(set) var selectedProject: LuunaProjectBinding?

    @Published private(set) var health = LuunaObservation<LuunaHealth>()
    @Published private(set) var projects = LuunaObservation<[LuunaProjectRecord]>()
    @Published private(set) var project = LuunaObservation<LuunaProjectView>()
    @Published private(set) var components = LuunaObservation<LuunaComponentStatus>()
    @Published private(set) var isRefreshing = false

    /// The connection-session counter. A read started under an older value is discarded.
    private(set) var generation = 0

    private let reader: LuunaRuntimeReading
    private let now: () -> Date
    private var token: String?
    private var refreshingGeneration: Int?

    /// `token` comes from `KeychainAPIKeyStore.luuna`; the caller reads it and passes it in.
    init(
        reader: LuunaRuntimeReading, origin: LuunaOrigin = .standard, token: String? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.reader = reader
        self.origin = origin
        self.token = Self.usable(token)
        self.hasToken = Self.usable(token) != nil
        self.now = now
    }

    /// Health is outside authentication, so "connected" needs a protected read (the project list) to have
    /// succeeded in this session as well.
    var isConnected: Bool { health.state.isSuccess && projects.state.isSuccess }

    /// The connection as a whole: the health check's state if it failed, otherwise the project list's.
    var connectionState: LuunaReadState { health.state.isSuccess ? projects.state : health.state }

    /// Use another origin or token. Any change starts a new session and clears every observation, since values
    /// read under the old origin or token belong to another authority.
    func connect(origin: LuunaOrigin, token: String?) {
        let token = Self.usable(token)
        guard origin != self.origin || token != self.token else { return }
        self.origin = origin
        self.token = token
        hasToken = token != nil
        startSession(clearingConnection: true)
    }

    /// Show another project (or none). Starts a new session and clears the project's observations; health and
    /// the project list keep theirs.
    func selectProject(_ binding: LuunaProjectBinding?) {
        guard binding != selectedProject else { return }
        selectedProject = binding
        startSession(clearingConnection: false)
    }

    /// Reads health, then the project list, then (for a selected project) its detail and component status.
    /// A failed step records its state on the steps that depend on it; their last good values stay.
    func refresh() async {
        let generation = generation
        guard refreshingGeneration != generation else { return }
        let binding = selectedProject
        guard let token else {
            fail(.unauthorized, health: true, project: binding != nil)
            return
        }
        let connection = LuunaConnection(origin: origin, token: token)
        refreshingGeneration = generation
        isRefreshing = true
        defer {
            if self.generation == generation {
                refreshingGeneration = nil
                isRefreshing = false
            }
        }

        guard let healthRead = await read(generation, { try await $0.health(connection) }) else { return }
        guard record(healthRead, in: \.health) else {
            fail(Self.dependentState(health.state), health: false, project: binding != nil)
            return
        }
        guard let listRead = await read(generation, { try await $0.projects(connection) }) else { return }
        guard record(listRead, in: \.projects, state: { $0.isEmpty ? .empty : .populated }) else {
            failProject(projects.state, if: binding != nil)
            return
        }
        guard let binding else { return }
        guard binding.origin == connection.origin else {
            failProject(.unavailable(.otherAuthority), if: true)
            return
        }
        await refreshProject(binding.projectID, connection, generation)
    }

    private func refreshProject(_ projectID: String, _ connection: LuunaConnection, _ generation: Int) async {
        async let detail = read(generation) { try await $0.project(projectID, connection) }
        async let status = read(generation) { try await $0.components(projectID, connection) }
        let (detailRead, statusRead) = await (detail, status)
        // One read can pass its own check and then wait for the other while the session changes.
        guard generation == self.generation else { return }
        if let detailRead {
            record(
                detailRead.flatMap { view in
                    view.project.id == projectID ? .success(view) : .failure(.undecodable)
                }, in: \.project)
        }
        if let statusRead { record(statusRead, in: \.components, state: { $0.enabled ? .populated : .uninitialized }) }
    }

    private func startSession(clearingConnection: Bool) {
        generation += 1
        refreshingGeneration = nil
        isRefreshing = false
        if clearingConnection {
            health = LuunaObservation()
            projects = LuunaObservation()
        }
        project = LuunaObservation()
        components = LuunaObservation()
    }

    /// Runs one read. Nil when the session changed meanwhile (the response is discarded) or the read was cancelled.
    private func read<Value>(
        _ generation: Int, _ operation: @escaping (LuunaRuntimeReading) async throws -> Value
    ) async -> Result<Value, LuunaReadFailure>? {
        let result: Result<Value, LuunaReadFailure>
        do {
            result = .success(try await operation(reader))
        } catch let failure as LuunaReadFailure {
            result = .failure(failure)
        } catch is CancellationError {
            return nil
        } catch {
            result = .failure(.unavailable(.transport(code: (error as NSError).code)))
        }
        guard generation == self.generation else {
            Log.luuna.info("Discarded a Luuna response from an earlier connection session")
            return nil
        }
        return result
    }

    /// Records a read on one observation; true when it succeeded.
    @discardableResult
    private func record<Value>(
        _ result: Result<Value, LuunaReadFailure>,
        in observation: ReferenceWritableKeyPath<LuunaStore, LuunaObservation<Value>>,
        state: (Value) -> LuunaReadState = { _ in .populated }
    ) -> Bool {
        switch result {
        case .success(let value):
            self[keyPath: observation].recordSuccess(value, state: state(value), at: now())
            return true
        case .failure(let failure):
            Log.luuna.notice("Luuna read failed: \(Self.label(failure.state), privacy: .public)")
            self[keyPath: observation].recordFailure(failure.state, at: now())
            return false
        }
    }

    private func fail(_ state: LuunaReadState, health includeHealth: Bool, project includeProject: Bool) {
        let date = now()
        if includeHealth { health.recordFailure(state, at: date) }
        projects.recordFailure(state, at: date)
        failProject(state, if: includeProject)
    }

    private func failProject(_ state: LuunaReadState, if selected: Bool) {
        guard selected else { return }
        let date = now()
        project.recordFailure(state, at: date)
        components.recordFailure(state, at: date)
    }

    /// What a failed health check means for the reads after it: the same state, except that an answer that is
    /// not Luuna's health (`partial`) makes the rest of the profile unsupported rather than partial.
    private static func dependentState(_ state: LuunaReadState) -> LuunaReadState {
        state == .partial ? .unsupported : state
    }

    private static func usable(_ token: String?) -> String? {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return token
    }

    /// A log label with no server content (a refusal's reason is left out).
    private static func label(_ state: LuunaReadState) -> String {
        switch state {
        case .refused(let refusal): return "refused (HTTP \(refusal.status))"
        case .unavailable(.shuttingDown): return "unavailable (shutting down)"
        default: return String(describing: state)
        }
    }
}
