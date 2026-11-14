import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class LuunaStoreTests: XCTestCase {
    private var reader: FakeLuunaReader!
    private var clock: Date!
    private let binding = LuunaProjectBinding(origin: .standard, projectID: "daily-workspace")

    override func setUp() async throws {
        reader = FakeLuunaReader()
        clock = Date(timeIntervalSince1970: 1_000)
    }

    private func makeStore(token: String? = "tok") -> LuunaStore {
        LuunaStore(reader: reader, origin: .standard, token: token) { [unowned self] in clock }
    }

    func testSuccessfulRefreshIsConnectedAndPopulated() async {
        let store = makeStore()
        store.selectProject(binding)

        await store.refresh()

        XCTAssertTrue(store.isConnected)
        XCTAssertEqual(store.health.value, LuunaFixtures.healthValue)
        XCTAssertEqual(store.projects.state, .populated)
        XCTAssertEqual(store.project.value?.project.id, "daily-workspace")
        XCTAssertEqual(store.components.state, .uninitialized, "Components that were never enabled")
        XCTAssertEqual(store.components.value?.enabled, false)
        XCTAssertEqual(store.projects.lastSuccessAt, clock)
        XCTAssertEqual(Set(reader.calls), ["health", "projects", "project", "components"])
        XCTAssertTrue(reader.connections.allSatisfy { $0.token == "tok" && $0.origin == .standard })
    }

    func testForeignProjectDetailIsInvalidAndCannotReplaceLastGoodDetail() async {
        var foreign = LuunaFixtures.projectValue
        foreign.project.id = "another-project"
        reader.set("project", Result<LuunaProjectView, LuunaReadFailure>.success(foreign))
        let store = makeStore()
        store.selectProject(binding)

        await store.refresh()
        XCTAssertEqual(store.project.state, .partial)
        XCTAssertNil(store.project.value)
        XCTAssertEqual(store.components.state, .uninitialized)

        reader.set("project", Result<LuunaProjectView, LuunaReadFailure>.success(LuunaFixtures.projectValue))
        await store.refresh()
        let lastSuccess = store.project.lastSuccessAt
        clock = clock.addingTimeInterval(60)
        reader.set("project", Result<LuunaProjectView, LuunaReadFailure>.success(foreign))

        await store.refresh()
        XCTAssertEqual(store.project.state, .partial)
        XCTAssertEqual(store.project.value?.project.id, binding.projectID)
        XCTAssertEqual(store.project.lastSuccessAt, lastSuccess)
        XCTAssertEqual(store.project.observedAt, clock)
        XCTAssertTrue(store.project.isShowingRetainedValue)
    }

    func testHealthOKButProjectsUnauthorizedIsNotConnected() async {
        reader.set("projects", Result<[LuunaProjectRecord], LuunaReadFailure>.failure(.unauthorized))
        let store = makeStore()
        store.selectProject(binding)

        await store.refresh()

        XCTAssertEqual(store.health.state, .populated)
        XCTAssertFalse(store.isConnected)
        XCTAssertEqual(store.connectionState, .unauthorized)
        XCTAssertEqual(store.project.state, .unauthorized)
        XCTAssertEqual(reader.calls, ["health", "projects"])
    }

    func testConnectionRefusedIsUnavailableAndKeepsTheLastSuccess() async {
        let store = makeStore()
        await store.refresh()
        let firstSuccess = clock
        clock = clock.addingTimeInterval(60)
        reader.set("health", Result<LuunaHealth, LuunaReadFailure>.failure(.unavailable(.cannotConnect)))

        await store.refresh()

        XCTAssertEqual(store.health.state, .unavailable(.cannotConnect))
        XCTAssertEqual(store.projects.state, .unavailable(.cannotConnect))
        XCTAssertEqual(store.projects.value, LuunaFixtures.projectsValue)
        XCTAssertEqual(store.projects.lastSuccessAt, firstSuccess)
        XCTAssertEqual(store.projects.observedAt, clock)
        XCTAssertTrue(store.projects.isShowingRetainedValue)
        XCTAssertFalse(store.isConnected)
    }

    func testResponseFromAnEarlierSessionIsDiscarded() async throws {
        let gate = reader.hold("health")
        let store = makeStore()
        let refresh = Task { await store.refresh() }
        try await gate.waitForArrival()
        let before = store.generation

        store.connect(origin: try LuunaOrigin(validating: "http://localhost:5000"), token: "other")
        gate.open()
        await refresh.value

        XCTAssertGreaterThan(store.generation, before)
        XCTAssertEqual(store.health.state, .unavailable(.notChecked))
        XCTAssertNil(store.health.value)
        XCTAssertNil(store.health.observedAt)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(reader.calls, ["health"], "Nothing more is read for the old session")
    }

    func testSwitchingProjectDiscardsTheOldProjectsDetail() async throws {
        let gate = reader.hold("project")
        let store = makeStore()
        store.selectProject(binding)
        let refresh = Task { await store.refresh() }
        try await gate.waitForArrival()

        store.selectProject(LuunaProjectBinding(origin: .standard, projectID: "luuna"))
        gate.open()
        await refresh.value

        XCTAssertNil(store.project.value)
        XCTAssertNil(store.components.value)
        XCTAssertEqual(store.project.state, .unavailable(.notChecked))
    }

    func testNoTokenIsUnauthorizedWithoutAnyRequest() async {
        let store = makeStore(token: "  ")
        await store.refresh()
        XCTAssertFalse(store.hasToken)
        XCTAssertEqual(store.health.state, .unauthorized)
        XCTAssertEqual(store.projects.state, .unauthorized)
        XCTAssertTrue(reader.calls.isEmpty)
    }

    func testEmptyProjectListIsEmptyAndStillConnected() async {
        reader.set("projects", Result<[LuunaProjectRecord], LuunaReadFailure>.success([]))
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.projects.state, .empty)
        XCTAssertTrue(store.isConnected)
    }

    func testProjectBoundToAnotherOriginIsNotReadWithThisToken() async throws {
        let store = makeStore()
        let elsewhere = try LuunaOrigin(validating: "http://127.0.0.1:9999")
        store.selectProject(LuunaProjectBinding(origin: elsewhere, projectID: "daily-workspace"))
        await store.refresh()
        XCTAssertEqual(store.project.state, .unavailable(.otherAuthority))
        XCTAssertFalse(reader.calls.contains("project"))
    }

    func testUnrecognizedHealthMakesTheProfileUnsupported() async {
        reader.set("health", Result<LuunaHealth, LuunaReadFailure>.failure(.undecodable))
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.health.state, .partial)
        XCTAssertEqual(store.projects.state, .unsupported)
        XCTAssertEqual(reader.calls, ["health"])
    }

    func testChangingTheTokenClearsObservations() async {
        let store = makeStore()
        await store.refresh()
        store.connect(origin: .standard, token: "rotated")
        XCTAssertNil(store.projects.value)
        XCTAssertFalse(store.isConnected)
        store.connect(origin: .standard, token: "rotated")
        XCTAssertEqual(store.generation, 1, "An unchanged origin and token keep the session")
    }
}
