import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class ProjectsStoreTests: XCTestCase {
    private var root: URL!
    private var appFolder: URL!
    private var registry: AssociationRegistry!
    private var luuna: LuunaStore!

    override func setUp() async throws {
        root = try makeTemporaryVault(self)
        appFolder = try makeTemporaryVault(self)
        try LoopVaultFixture.populate(root)
        registry = AssociationRegistry(directory: WorkspaceDirectory(url: appFolder))
        luuna = LuunaStore(reader: FakeLuunaReader(), token: "tok")
    }

    private func makeStore() -> ProjectsStore {
        ProjectsStore(registry: registry, luuna: luuna, vaultRoot: root)
    }

    func testHubsAreSortedByTitleAndSelectionDoesNotInferALuunaBinding() async throws {
        let native: [LuunaProjectRecord] = try JSONDecoder().decode(
            [LuunaProjectRecord].self,
            from: Data(#"[{"id":"alpha","name":"Alpha","revision":1}]"#.utf8))
        let reader = FakeLuunaReader()
        reader.set("projects", .success(native))
        luuna = LuunaStore(reader: reader, token: "tok")
        await luuna.refresh()
        XCTAssertEqual(luuna.projects.value?.map(\.name), ["Alpha"])
        let store = makeStore()
        await store.refresh()

        XCTAssertEqual(store.hubs?.state, .populated)
        XCTAssertEqual(store.hubs?.value.map(\.title), ["Alpha", "Project X"])

        store.select("alpha-hub")
        let alpha = try XCTUnwrap(store.detail)
        XCTAssertEqual(alpha.hub.projectKey, "alpha")
        XCTAssertNil(alpha.association)
        XCTAssertNil(luuna.selectedProject, "A hub name or project key cannot establish a native binding")

        store.select("x")
        XCTAssertEqual(store.detail?.hub.title, "Project X")
        XCTAssertNil(luuna.selectedProject)
    }

    func testAssociationEditsRoundTripThroughTheRegistry() async throws {
        let store = makeStore()
        await store.refresh()
        store.select("x")

        XCTAssertNil(store.addCheckout(path: "~/github/x/", label: " X app "))
        XCTAssertNil(store.addCheckout(path: "~/github/x", label: nil), "The same checkout is not added twice")
        let binding = LuunaProjectBinding(origin: .standard, projectID: "daily-workspace")
        XCTAssertNil(store.bindLuuna(origin: .standard, projectID: " daily-workspace "))

        let saved = try registry.load().value
        let expected = (("~/github/x" as NSString).expandingTildeInPath as NSString).standardizingPath
        XCTAssertEqual(saved.map(\.hubPath), ["01-projects/x/x.md"])
        XCTAssertEqual(saved.first?.checkouts, [RepositoryCheckoutReference(path: expected, label: "X app")])
        XCTAssertEqual(saved.first?.luuna, binding)
        XCTAssertEqual(store.detail?.association, saved.first)
        XCTAssertEqual(luuna.selectedProject, binding, "The selected hub's binding drives the Luuna panel")

        let reopened = makeStore()
        XCTAssertEqual(reopened.associations, saved)
        XCTAssertEqual(reopened.associationsStatus, .loaded)

        XCTAssertNil(store.removeCheckout(path: expected))
        XCTAssertNil(store.unbindLuuna())
        XCTAssertEqual(try registry.load().value, [], "An empty association is removed")
        XCTAssertNil(luuna.selectedProject)
    }

    func testEditsNeedASelectionAndAFullPath() async {
        let store = makeStore()
        await store.refresh()

        XCTAssertEqual(store.addCheckout(path: "/tmp/x"), "Select a project first.")
        store.select("x")
        XCTAssertNotNil(store.addCheckout(path: "github/x"))
        XCTAssertNotNil(store.bindLuuna(origin: .standard, projectID: "  "))
        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.url.path), "Nothing was saved")
    }

    func testNewerRegistryIsReadOnlyAndNeverOverwritten() async throws {
        let newer = #"{"version": 99, "associations": []}"#
        try write(newer, to: registry.url)
        let store = makeStore()
        await store.refresh()
        store.select("x")

        XCTAssertEqual(store.associationsStatus, .readOnly(version: 99))
        XCTAssertFalse(store.canEditAssociations)
        let refusal = try XCTUnwrap(store.addCheckout(path: "/tmp/x"))
        XCTAssertTrue(refusal.contains("newer version"), refusal)
        XCTAssertEqual(store.associationMessage, refusal)
        XCTAssertNotNil(store.bindLuuna(origin: .standard, projectID: "p"))
        XCTAssertEqual(try contents(of: registry.url), newer)
    }

    func testNewerRegistryWrittenAfterLaunchBecomesReadOnlyOnSave() async throws {
        let store = makeStore()
        await store.refresh()
        store.select("x")
        let newer = #"{"version": 2, "associations": []}"#
        try write(newer, to: registry.url)

        XCTAssertNotNil(store.addCheckout(path: "/tmp/x"))

        XCTAssertEqual(store.associationsStatus, .readOnly(version: 2))
        XCTAssertEqual(try contents(of: registry.url), newer)
        XCTAssertEqual(store.associations, [])
    }

    func testCorruptRegistryCannotBindAProjectAndIsMovedAside() async throws {
        try write("not json", to: registry.url)

        let store = makeStore()

        guard case .movedAside(let aside) = store.associationsStatus else {
            return XCTFail("Expected movedAside, got \(store.associationsStatus)")
        }
        XCTAssertEqual(try contents(of: aside), "not json")
        XCTAssertTrue(store.canEditAssociations)
        XCTAssertTrue(store.associations.isEmpty)
        XCTAssertNil(store.association(forHubPath: "01-projects/x/x.md"))
        await store.refresh()
        store.select("x")
        XCTAssertNil(store.detail?.association)
        XCTAssertNil(luuna.selectedProject)
    }

    func testVaultChangeClearsHubsAndSelection() async throws {
        let store = makeStore()
        await store.refresh()
        store.select("x")
        XCTAssertNotNil(store.detail)

        store.setVaultRoot(try makeTemporaryVault(self))
        XCTAssertNil(store.hubs)
        XCTAssertNil(store.detail)
        XCTAssertNil(store.selectedSlug)

        await store.refresh()
        guard case .unavailable = store.hubs?.state else {
            return XCTFail("No 01-projects/ must be unavailable, got \(String(describing: store.hubs?.state))")
        }
    }
}

@MainActor
final class AppModelLuunaTests: XCTestCase {
    private var directory: WorkspaceDirectory!
    private var keys: FakeKeyStore!
    private var reader: FakeLuunaReader!
    private var workReader: FakeLuunaWorkReader!

    override func setUp() async throws {
        directory = WorkspaceDirectory(url: try makeTemporaryVault(self))
        keys = FakeKeyStore()
        reader = FakeLuunaReader()
        workReader = FakeLuunaWorkReader()
    }

    private func makeModel(tasks: InMemoryTaskPersistence = InMemoryTaskPersistence()) -> AppModel {
        AppModel(
            dependencies: .test(
                tasks: tasks, directory: directory, luunaReader: reader, luunaWorkReader: workReader, luunaKeys: keys))
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for native Luuna read")
    }

    private func fixture<Value: Decodable>(_ json: String) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }

    func testLaunchConnectsWithTheSavedOriginAndToken() throws {
        let origin = try LuunaOrigin(validating: "http://localhost:4300")
        try LuunaHostAccessStore(directory: directory).save(LuunaHostAccess(origin: origin))
        keys.key = "saved-token"

        let model = makeModel()

        XCTAssertEqual(model.luuna.origin, origin)
        XCTAssertTrue(model.luuna.hasToken)
        XCTAssertNil(model.luunaSettingsNotice)
    }

    func testLaunchFallsBackToTheStandardOrigin() {
        let model = makeModel()

        XCTAssertEqual(model.luuna.origin, .standard)
        XCTAssertFalse(model.luuna.hasToken)
    }

    func testConnectLuunaRejectsANonLoopbackOriginAndSavesNothing() {
        let model = makeModel()

        let refusal = model.connectLuuna(origin: "http://example.com:4242", token: "secret")

        XCTAssertEqual(refusal, LuunaOriginError.notHTTPLoopback.errorDescription)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.luunaHostURL.path))
        XCTAssertNil(keys.key)
        XCTAssertEqual(model.luuna.origin, .standard)
        XCTAssertNotNil(model.connectLuuna(origin: "https://127.0.0.1:4242", token: nil))
        XCTAssertNotNil(model.connectLuuna(origin: "http://127.0.0.1:4242/api", token: nil))
    }

    func testConnectLuunaSavesAValidOriginAndTokenAndReconnects() throws {
        let model = makeModel()
        let before = model.luuna.generation

        XCTAssertNil(model.connectLuuna(origin: " http://localhost:5000 ", token: "secret"))

        let origin = try LuunaOrigin(validating: "http://localhost:5000")
        XCTAssertEqual(try LuunaHostAccessStore(directory: directory).load().value?.origin, origin)
        XCTAssertEqual(keys.key, "secret")
        XCTAssertEqual(model.luuna.origin, origin)
        XCTAssertTrue(model.luuna.hasToken)
        XCTAssertGreaterThan(model.luuna.generation, before)
        XCTAssertFalse(try contents(of: directory.luunaHostURL).contains("secret"), "The token never reaches a file")

        XCTAssertNil(model.connectLuuna(origin: "http://localhost:5000", token: nil), "nil keeps the saved token")
        XCTAssertEqual(keys.key, "secret")
        XCTAssertTrue(model.luuna.hasToken)

        XCTAssertNil(model.connectLuuna(origin: "http://localhost:5000", token: ""))
        XCTAssertNil(keys.key, "An empty token removes it")
        XCTAssertFalse(model.luuna.hasToken)
    }

    func testVaultChangePointsOpenLoopsAndProjectsAtTheNewVault() async throws {
        let root = try makeTemporaryVault(self)
        try LoopVaultFixture.populate(root)
        let model = makeModel()
        XCTAssertNil(model.openLoops.vaultRoot)

        model.useVault(at: root)

        XCTAssertNotNil(model.openLoops.vaultRoot)
        XCTAssertEqual(model.openLoops.vaultRoot, model.projects.vaultRoot)
        await model.openLoops.refresh()
        await model.projects.refresh()
        XCTAssertEqual(model.openLoops.observations[.local]?.state, .empty)
        XCTAssertEqual(model.projects.hubs?.value.count, 2)
    }

    func testGlobalHomeRefreshesWithoutVaultOrSelectedHub() async throws {
        keys.key = "saved-token"
        let home: LuunaHome = try fixture(
            #"{"projects":[{"id":"p","name":"Native project","repositories":[]}],"blockers":[]}"#)
        workReader.set("homeAll", .success(home))
        let model = makeModel()

        model.refreshSources()
        try await waitUntil { model.luunaWork.globalHome.value == home }

        XCTAssertNil(model.projects.selectedSlug)
        XCTAssertEqual(model.luunaWork.globalHome.state, .populated)
        XCTAssertEqual(workReader.calls.filter { $0.name == "homeAll" }.map(\.connection.token), ["saved-token"])
        XCTAssertFalse(workReader.calls.contains { $0.name == "board" || $0.name == "tickets" })
    }

    func testBindingTracksProjectSelectionAndVaultSwitchWithoutTouchingLocalTasks() async throws {
        keys.key = "saved-token"
        let tasks = InMemoryTaskPersistence()
        let model = makeModel(tasks: tasks)
        let first = try makeTemporaryVault(self)
        let second = try makeTemporaryVault(self)
        try LoopVaultFixture.populate(first)
        try LoopVaultFixture.populate(second)
        model.useVault(at: first)
        await model.projects.refresh()
        try await waitUntil { model.projects.hubs?.value.contains(where: { $0.slug == "x" }) == true }
        model.projects.select("x")
        XCTAssertEqual(model.projects.detail?.hub.path, "01-projects/x/x.md")
        XCTAssertNil(model.projects.bindLuuna(origin: .standard, projectID: "first"))
        try await waitUntil { model.luunaWork.board.state == .empty }
        XCTAssertEqual(workReader.calls.filter { $0.name == "board" }.map(\.projectID), ["first"])

        model.projects.select("alpha-hub")
        XCTAssertNil(model.luunaWork.board.value)
        XCTAssertNil(model.luunaWork.tickets.value)
        model.projects.select("x")
        XCTAssertNil(model.projects.bindLuuna(origin: .standard, projectID: "second"))
        try await waitUntil { self.workReader.calls.contains { $0.name == "board" && $0.projectID == "second" } }

        model.useVault(at: second)
        XCTAssertNil(model.projects.detail)
        XCTAssertNil(model.luunaWork.board.value, "An earlier vault's project cannot survive a switch")
        await model.projects.refresh()
        await model.projects.refresh()
        try await waitUntil { model.projects.hubs?.value.contains(where: { $0.slug == "alpha-hub" }) == true }
        model.projects.select("alpha-hub")
        XCTAssertNil(model.luunaWork.home.value)
        XCTAssertTrue(tasks.stored.items.isEmpty)
        XCTAssertEqual(tasks.saveCount, 0)
    }

    func testForeignBindingAndSettingsChangesClearAuthorityScopedWork() async throws {
        keys.key = "first-token"
        let root = try makeTemporaryVault(self)
        try LoopVaultFixture.populate(root)
        let model = makeModel()
        model.useVault(at: root)
        await model.projects.refresh()
        try await waitUntil { model.projects.hubs?.value.contains(where: { $0.slug == "x" }) == true }
        model.projects.select("x")
        XCTAssertEqual(model.projects.detail?.hub.path, "01-projects/x/x.md")
        XCTAssertNil(model.projects.bindLuuna(origin: .standard, projectID: "first"))
        try await waitUntil { model.luunaWork.board.state == .empty }
        await model.luunaWork.refreshGlobalHome()
        XCTAssertNotNil(model.luunaWork.globalHome.value)

        let foreign = try LuunaOrigin(validating: "http://localhost:5050")
        XCTAssertNil(model.projects.bindLuuna(origin: foreign, projectID: "foreign"))
        XCTAssertNil(model.luunaWork.board.value)
        let callCount = workReader.calls.count
        await model.luunaWork.refresh()
        XCTAssertEqual(workReader.calls.count, callCount, "A foreign binding must never be queried")

        XCTAssertNil(model.connectLuuna(origin: "http://localhost:5050", token: "second-token"))
        XCTAssertNil(model.luunaWork.globalHome.value, "The prior origin's Home must be discarded")
        try await waitUntil {
            self.workReader.calls.contains {
                $0.name == "board" && $0.projectID == "foreign" && $0.connection.token == "second-token"
            }
        }
        try await waitUntil { model.luunaWork.globalHome.state == .empty }
        let gate = workReader.hold("homeAll")
        let staleRead = Task { await model.luunaWork.refreshGlobalHome() }
        try await gate.waitForArrival()
        XCTAssertNil(model.connectLuuna(origin: "http://localhost:5050", token: ""))
        XCTAssertNil(model.luunaWork.board.value)
        XCTAssertNil(model.luunaWork.globalHome.value)
        gate.open()
        await staleRead.value
        XCTAssertNil(model.luunaWork.globalHome.value, "An in-flight read from the old token must be discarded")
        let noTokenCallCount = workReader.calls.count
        await model.luunaWork.refresh()
        await model.luunaWork.refreshGlobalHome()
        XCTAssertEqual(workReader.calls.count, noTokenCallCount, "No native read without an authenticated connection")
    }
}
