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

    func testHubsAreSortedByTitleAndSeedsAreFilteredByProjectKey() async throws {
        let store = makeStore()
        await store.refresh()

        XCTAssertEqual(store.hubs?.state, .populated)
        XCTAssertEqual(store.hubs?.value.map(\.title), ["Alpha", "Project X"])

        store.select("alpha-hub")
        let alpha = try XCTUnwrap(store.detail)
        XCTAssertEqual(alpha.hub.projectKey, "alpha", "The frontmatter project wins over the slug")
        XCTAssertEqual(alpha.issues.map(\.id), ["brain-b2"])
        XCTAssertEqual(alpha.plans.map(\.id), ["plan-1"], "A plan takes its seed issue's project")
        XCTAssertEqual(alpha.plots.map(\.id), ["plot-5678efgh"], "A file in the hub's folder")
        XCTAssertEqual(alpha.issues.first?.status, "open")

        store.select("x")
        let x = try XCTUnwrap(store.detail)
        XCTAssertEqual(x.issues.map(\.id), ["brain-a1"])
        XCTAssertEqual(x.plans, [])
        XCTAssertEqual(x.plots.map(\.id), ["plot-1234abcd"], "Attaches the project's Seeds issue")
        XCTAssertEqual(x.seedsState, .populated)
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

    func testCorruptRegistryIsMovedAsideAndReported() throws {
        try write("not json", to: registry.url)

        let store = makeStore()

        guard case .movedAside(let aside) = store.associationsStatus else {
            return XCTFail("Expected movedAside, got \(store.associationsStatus)")
        }
        XCTAssertEqual(try contents(of: aside), "not json")
        XCTAssertTrue(store.canEditAssociations)
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

    override func setUp() async throws {
        directory = WorkspaceDirectory(url: try makeTemporaryVault(self))
        keys = FakeKeyStore()
        reader = FakeLuunaReader()
    }

    private func makeModel() -> AppModel {
        AppModel(dependencies: .test(directory: directory, luunaReader: reader, luunaKeys: keys))
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
        XCTAssertEqual(model.openLoops.observations[.org]?.state, .populated)
        XCTAssertEqual(model.projects.hubs?.value.count, 2)
    }
}
