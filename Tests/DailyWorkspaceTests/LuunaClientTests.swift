import DailyCore
import XCTest

@testable import DailyWorkspace

/// The transport, against `LuunaStubProtocol`. No request leaves the process and no runtime is touched.
final class LuunaRuntimeClientTests: XCTestCase {
    private var client: LuunaRuntimeClient!

    override func setUp() {
        client = LuunaRuntimeClient(protocolClasses: [LuunaStubProtocol.self])
    }

    override func tearDown() {
        client = nil
    }

    private func expectFailure<Value>(
        _ expected: LuunaReadFailure, file: StaticString = #filePath, line: UInt = #line,
        _ operation: () async throws -> Value
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LuunaReadFailure, expected, file: file, line: line)
        }
    }

    func testRequestsAreBearerAuthenticatedJSONGetsToTheTypeScriptPaths() async throws {
        LuunaStubProtocol.reset { request in
            switch request.url?.path {
            case "/api/v1/health": return .http(status: 200, body: LuunaFixtures.health)
            case "/api/v1/projects": return .http(status: 200, body: LuunaFixtures.projects)
            case let path? where path.hasSuffix("/components"):
                return .http(status: 200, body: LuunaFixtures.components)
            default: return .http(status: 200, body: LuunaFixtures.project)
            }
        }
        let connection = LuunaConnection(origin: try LuunaOrigin(validating: "http://[::1]:5151"), token: "tok-1")

        let health = try await client.health(connection)
        let list = try await client.projects(connection)
        _ = try await client.project("a b/c?d", connection)
        _ = try await client.components("daily-workspace", connection)

        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(list.map(\.id), ["daily-workspace"])
        let requests = LuunaStubProtocol.requests
        XCTAssertEqual(
            requests.map { $0.url?.absoluteString },
            [
                "http://[::1]:5151/api/v1/health", "http://[::1]:5151/api/v1/projects",
                "http://[::1]:5151/api/v1/projects/a%20b%2Fc%3Fd",
                "http://[::1]:5151/api/v1/projects/daily-workspace/components",
            ])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.httpBody)
        }
    }

    func testSessionHasNoCacheCookiesOrCredentialStorage() {
        let configuration = client.configuration
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertNil(configuration.urlCredentialStorage)
        let request = LuunaRuntimeClient.request(LuunaEndpoint.health, .fixture)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testRedirectIsRefusedAndTheTargetIsNeverRequested() async {
        let target = URL(string: "http://127.0.0.1:9/api/v1/projects")!
        LuunaStubProtocol.reset { request in
            request.url == target
                ? .http(status: 200, body: LuunaFixtures.projects) : .redirect(status: 307, to: target)
        }

        await expectFailure(.unavailable(.redirectRefused)) { try await client.projects(.fixture) }

        XCTAssertEqual(LuunaStubProtocol.requests.map { $0.url?.path }, ["/api/v1/projects"])
    }

    func testRedirectGuardAnswersNil() {
        let session = URLSession(configuration: .ephemeral)
        let request = URLRequest(url: URL(string: "http://127.0.0.1:4242/api/v1/projects")!)
        let task = session.dataTask(with: request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
            headerFields: ["Location": "http://example.com"])!
        var answered = false
        LuunaRedirectGuard().urlSession(
            session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "http://example.com")!)
        ) { next in
            answered = true
            XCTAssertNil(next)
        }
        XCTAssertTrue(answered)
        session.invalidateAndCancel()
    }

    func testStatusesMapToSourceStates() async {
        let cases: [(reply: LuunaStubProtocol.Reply, expected: LuunaReadFailure)] = [
            (.http(status: 401, body: Data(#"{"error":"authentication required"}"#.utf8)), .unauthorized),
            (.http(status: 403, body: Data()), .unauthorized),
            (.http(status: 404, body: Data(#"{"error":"not found"}"#.utf8)), .unsupported),
            (
                .http(status: 422, body: Data(#"{"error":"limit must be an integer"}"#.utf8)),
                .refused(LuunaRefusal(status: 422, reason: "limit must be an integer"))
            ),
            (
                .http(status: 500, body: Data(#"{"error":"secret detail"}"#.utf8)),
                .unavailable(.serverError(status: 500))
            ),
        ]
        for (reply, expected) in cases {
            LuunaStubProtocol.reset { _ in reply }
            await expectFailure(expected) { try await client.projects(.fixture) }
        }
    }

    func testTransportFailuresAreUnavailable() async {
        LuunaStubProtocol.reset { _ in .failure(.cannotConnectToHost) }
        await expectFailure(.unavailable(.cannotConnect)) { try await client.health(.fixture) }
        LuunaStubProtocol.reset { _ in .failure(.timedOut) }
        await expectFailure(.unavailable(.timedOut)) { try await client.health(.fixture) }
    }

    func testUndecodableSuccessIsPartial() async {
        LuunaStubProtocol.reset { _ in .http(status: 200, body: Data("<html>not luuna</html>".utf8)) }
        await expectFailure(.undecodable) { try await client.health(.fixture) }
        XCTAssertEqual(LuunaReadFailure.undecodable.state, .partial)
    }

    func testConnectionNeverPrintsItsToken() {
        let connection = LuunaConnection(origin: .standard, token: "sk-very-secret")
        XCTAssertFalse(String(describing: connection).contains("sk-very-secret"))
        XCTAssertFalse(String(reflecting: connection).contains("sk-very-secret"))
        XCTAssertFalse(Mirror(reflecting: connection).children.contains { "\($0.value)".contains("sk-very-secret") })
    }

    @MainActor
    func testHealthOKButProjectListRejectedIsNotConnected() async {
        LuunaStubProtocol.reset { request in
            request.url?.path == "/api/v1/health"
                ? .http(status: 200, body: LuunaFixtures.health)
                : .http(status: 401, body: Data(#"{"error":"authentication required"}"#.utf8))
        }
        let store = LuunaStore(reader: client, token: "wrong-token")

        await store.refresh()

        XCTAssertEqual(store.health.state, .populated)
        XCTAssertEqual(store.projects.state, .unauthorized)
        XCTAssertEqual(store.connectionState, .unauthorized)
        XCTAssertFalse(store.isConnected)
    }
}

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
