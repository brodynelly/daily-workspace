import XCTest

@testable import DailyCore

final class LuunaOriginTests: XCTestCase {
    func testAcceptsLoopbackOriginsAsTheTypeScriptClientDoes() throws {
        let accepted: [(String, String)] = [
            ("http://127.0.0.1:4242", "http://127.0.0.1:4242"),
            ("http://localhost:4242/", "http://localhost:4242"),
            ("http://[::1]:4242", "http://[::1]:4242"),
            ("HTTP://LOCALHOST:8080", "http://localhost:8080"),
            ("  http://127.0.0.1:4242\n", "http://127.0.0.1:4242"),
            ("http://127.0.0.1", "http://127.0.0.1"),
            ("http://127.0.0.1:80", "http://127.0.0.1"),
            ("http://127.0.0.1:4242/?#", "http://127.0.0.1:4242"),
        ]
        for (text, origin) in accepted {
            XCTAssertEqual(try LuunaOrigin(validating: text).description, origin, text)
        }
        XCTAssertNil(try LuunaOrigin(validating: "http://127.0.0.1").port)
    }

    func testRejectsAnythingButABareHTTPLoopbackOrigin() {
        let rejected: [(String, LuunaOriginError)] = [
            ("https://127.0.0.1:4242", .notHTTPLoopback),
            ("http://example.com:4242", .notHTTPLoopback),
            ("http://127.0.0.2:4242", .notHTTPLoopback),
            ("http://0.0.0.0:4242", .notHTTPLoopback),
            ("http://192.168.1.10:4242", .notHTTPLoopback),
            ("http://localhost.:4242", .notHTTPLoopback),
            ("http://127.1:4242", .notHTTPLoopback),
            ("127.0.0.1:4242", .notHTTPLoopback),
            ("", .notHTTPLoopback),
            ("http://user:pass@127.0.0.1:4242", .notBareOrigin),
            ("http://token@localhost:4242", .notBareOrigin),
            ("http://127.0.0.1:4242/api", .notBareOrigin),
            ("http://127.0.0.1:4242/api/v1/", .notBareOrigin),
            ("http://127.0.0.1:4242?token=x", .notBareOrigin),
            ("http://127.0.0.1:4242#frag", .notBareOrigin),
            ("http://127.0.0.1:4242\\x", .notBareOrigin),
            ("http://127.0.0.1:70000", .malformed),
            ("http://127.0.0.1:42a", .malformed),
            ("http://[::1", .malformed),
        ]
        for (text, error) in rejected {
            XCTAssertThrowsError(try LuunaOrigin(validating: text), text) {
                XCTAssertEqual($0 as? LuunaOriginError, error, text)
            }
        }
    }

    func testDefaultIsLoopbackPort4242() {
        XCTAssertEqual(LuunaOrigin.standard.description, "http://127.0.0.1:4242")
        XCTAssertEqual(LuunaOrigin.standard.url.absoluteString, "http://127.0.0.1:4242")
        XCTAssertEqual(LuunaHostAccess().origin, .standard)
    }

    func testAPIURLsEncodeOpaqueIDsAsOneSegment() {
        XCTAssertEqual(LuunaOrigin.standard.apiURL("/health").absoluteString, "http://127.0.0.1:4242/api/v1/health")
        XCTAssertEqual(LuunaOrigin.pathSegment("a b/c?d#é"), "a%20b%2Fc%3Fd%23%C3%A9")
        XCTAssertEqual(LuunaOrigin.pathSegment("daily-workspace_1.x!~*'()"), "daily-workspace_1.x!~*'()")
    }

    func testCodableRoundTripAndInvalidStoredOriginsDoNotDecode() throws {
        let origin = try LuunaOrigin(validating: "http://[::1]:5151")
        let data = try JSONEncoder().encode(origin)
        XCTAssertEqual(String(bytes: data, encoding: .utf8), #""http:\/\/[::1]:5151""#)
        XCTAssertEqual(try JSONDecoder().decode(LuunaOrigin.self, from: data), origin)
        XCTAssertThrowsError(try JSONDecoder().decode(LuunaOrigin.self, from: Data(#""https://evil.example""#.utf8)))
    }
}

final class LuunaDecodingTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// The body of the runtime's `health` handler.
    func testHealth() throws {
        let health = try decode(
            LuunaHealth.self,
            """
            {"status":"ok","pi_version":"0.66.1","pi_version_status":"required; checked on every run",
             "native_execution":true,"build_identity":"sha256:5d0c9a","build_rustc":"rustc 1.91.0 (f8297e351 2025-10-28)",
             "build_rustc_sha256":"8e1f","build_rustc_wrapper":"none","build_flags":"profile=release opt-level=3"}
            """)
        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(health.piVersion, "0.66.1")
        XCTAssertEqual(health.nativeExecution, true)
        XCTAssertEqual(health.buildRustcSHA256, "8e1f")
        XCTAssertEqual(try decode(LuunaHealth.self, #"{"status":"ok","pi_version":"0.60.0"}"#).buildIdentity, nil)
    }

    func testProjectListKeepsIDsOpaqueAndAcceptsNulls() throws {
        let list = try decode(
            [LuunaProjectRecord].self,
            """
            [{"id":"daily-workspace","name":"Daily Workspace","revision":3,"manifest_hash":"sha256:ab12",
              "created_at":"2026-11-02T09:14:03.512Z","updated_at":"2026-11-12T18:50:20.997716Z","owner":"future"},
             {"id":"luuna","name":"Luuna","revision":1,"manifest_hash":null,
              "created_at":"2026-10-01T08:00:00Z","updated_at":"2026-10-01T08:00:00Z"}]
            """)
        XCTAssertEqual(list.map(\.id), ["daily-workspace", "luuna"])
        XCTAssertNil(list[1].manifestHash)
        XCTAssertNotNil(LuunaTimestamp.date(list[0].updatedAt))
        XCTAssertNotNil(LuunaTimestamp.date(list[1].createdAt))
        XCTAssertEqual(try decode([LuunaProjectRecord].self, "[]"), [])
    }

    /// A `ProjectView` with every documented part, plus fields this app does not know.
    func testProjectViewIgnoresUnknownFieldsAndKeepsUnknownValues() throws {
        let view = try decode(LuunaProjectView.self, Self.projectView)
        XCTAssertEqual(view.project.name, "Daily Workspace")
        let repository = try XCTUnwrap(view.repositories?.first)
        XCTAssertEqual(repository.repositoryID, "app")
        XCTAssertEqual(repository.observation?.dirty?.untracked, 2)
        XCTAssertEqual(repository.observation?.identity?.rootCommits, ["0a1b2c"])
        XCTAssertEqual(view.manifest?.baseCommits, ["app": "9f8e7d", "my_repo": "1234ab"], "Map keys stay verbatim")
        XCTAssertEqual(view.manifest?.manifest?.repositories?.first?.execution, "sandboxed-vm")
        XCTAssertNil(view.discovery)
        XCTAssertEqual(view.prerequisites?.first?.next, "POST /api/v1/projects/daily-workspace/tickets")
    }

    /// The body of the runtime's component `status` handler: a pinned adapter and a per-repository Roots row.
    func testComponentStatus() throws {
        let status = try decode(LuunaComponentStatus.self, Self.componentStatus)
        XCTAssertTrue(status.enabled)
        XCTAssertNil(status.reason)
        let adapters = try XCTUnwrap(status.adapters)
        XCTAssertEqual(adapters.map(\.name), ["missions", "roots", "orbit-next"])
        XCTAssertEqual(adapters[0].dataPath, "/Users/me/.luuna/projects/daily-workspace/.luuna/missions")
        XCTAssertEqual(adapters[1].storeStatus, "uninitialized")
        XCTAssertEqual(adapters[1].repositoryID, "app")
        XCTAssertNil(adapters[1].version)
        XCTAssertEqual(adapters[2].status?.rawValue, "quarantined", "An unknown status is kept verbatim")

        let disabled = try decode(
            LuunaComponentStatus.self,
            #"{"enabled":false,"workspace_path":"/x","reason":"Activation is incomplete; retry to reconcile it","adapters":[]}"#
        )
        XCTAssertFalse(disabled.enabled)
        XCTAssertEqual(disabled.reason, "Activation is incomplete; retry to reconcile it")
    }

    func testMissingIdentityFailsToDecode() {
        XCTAssertThrowsError(try decode(LuunaProjectRecord.self, #"{"name":"no id"}"#))
        XCTAssertThrowsError(try decode(LuunaComponentStatus.self, #"{"adapters":[]}"#))
    }

    static let projectView = """
        {"project":{"id":"daily-workspace","name":"Daily Workspace","revision":3,"manifest_hash":"sha256:ab12",
                    "created_at":"2026-11-02T09:14:03.512Z","updated_at":"2026-11-12T18:50:20.997716Z"},
         "repositories":[{"project_id":"daily-workspace","repository_id":"app","local_path":"/Users/me/src/app",
           "observation":{"local_path":"/Users/me/src/app",
             "identity":{"remote":"git@github.com:me/app.git","push_remote":null,"root_commits":["0a1b2c"],"shallow":false},
             "head_commit":"9f8e7d","branch":"main","remote_default_branch":"main","local_branches":["main","wip"],
             "dirty":{"staged":0,"unstaged":1,"untracked":2,"conflicted":0,"paths":["README.md"],"truncated":false},
             "git_version":"2.47.1","observed_at":"2026-11-12T18:49:59Z","worktrees":[]},
           "registered_at":"2026-11-02T09:14:03Z"}],
         "manifest":{"project_id":"daily-workspace","revision":3,"hash":"sha256:ab12",
           "manifest":{"schema_version":"1","id":"daily-workspace","name":"Daily Workspace","revision":3,
             "repositories":[{"id":"app","remote":"git@github.com:me/app.git","default_branch":"main",
               "profiles":["swift"],"execution":"sandboxed-vm",
               "checks":[{"id":"test","executable":"swift","args":["test"],"required":true,"timeout_seconds":600,
                          "capabilities":[]}]}],
             "relationships":[],"policy":{"approval":"plan","testing_prerequisite":true,"publish":"automatic_pr",
               "merge":"human","max_explorers":2,"max_implementers":1,"max_task_repairs":2}},
           "base_commits":{"app":"9f8e7d","my_repo":"1234ab"},"confirmed_at":"2026-11-03T10:00:00Z"},
         "discovery":null,
         "prerequisites":[{"kind":"testing_setup","project_id":"daily-workspace","repository_id":"app",
           "baseline_id":"b-1","reason":"no required check executed a test",
           "next":"POST /api/v1/projects/daily-workspace/tickets"}],
         "future_panel":{"anything":[1,2,3]}}
        """

    static let componentStatus = """
        {"enabled":true,"workspace_path":"/Users/me/.luuna/projects/daily-workspace","reason":null,
         "adapters":[
          {"name":"missions","backend":"native-go","status":"available","version":"0.4.2",
           "executable_path":"/opt/luuna/bin/missions","sha256":"77aa","source_commit":"e09b7b3",
           "source_path":"/opt/luuna/src/missions","data_path":"/Users/me/.luuna/projects/daily-workspace/.luuna/missions"},
          {"name":"roots","repository_id":"app","repository_path":"/Users/me/src/app","data_path":"/Users/me/src/app/.roots",
           "config_path":"/Users/me/src/app/.roots/config.toml","store_status":"uninitialized","backend":"native-rust",
           "backend_status":"available","status":"uninitialized","version":null,"executable_path":null,"sha256":null,
           "source_commit":null,"source_path":null},
          {"name":"orbit-next","backend":"native","status":"quarantined","version":"1","executable_path":"/x",
           "sha256":"00","source_commit":null,"source_path":null,"data_path":null,"new_field":true}]}
        """
}

final class LuunaFailureTests: XCTestCase {

    func testEveryFailureHasOneState() {
        XCTAssertEqual(LuunaReadFailure.undecodable.state, .partial)
        XCTAssertEqual(LuunaReadFailure.unauthorized.state, .unauthorized)
        XCTAssertEqual(LuunaReadFailure.unavailable(.timedOut).state, .unavailable(.timedOut))
        XCTAssertFalse(LuunaReadState.partial.isSuccess)
        XCTAssertTrue(LuunaReadState.uninitialized.isSuccess)
    }

    func testObservationKeepsTheLastGoodValueAcrossFailures() {
        var observation = LuunaObservation<[String]>()
        XCTAssertEqual(observation.state, .unavailable(.notChecked))
        XCTAssertNil(observation.observedAt)

        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        observation.recordSuccess(["a"], at: first)
        observation.recordFailure(.partial, at: second)

        XCTAssertEqual(observation.state, .partial)
        XCTAssertEqual(observation.value, ["a"])
        XCTAssertEqual(observation.lastSuccessAt, first)
        XCTAssertEqual(observation.observedAt, second)
        XCTAssertTrue(observation.isShowingRetainedValue)
    }
}

final class AssociationRegistryTests: XCTestCase {
    private var folder: URL!
    private var directory: WorkspaceDirectory!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("luuna-\(UUID().uuidString)")
        directory = WorkspaceDirectory(url: folder.appendingPathComponent("daily-workspace"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func contents(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func testFilesLiveInTheAppFolder() {
        XCTAssertEqual(directory.associationsURL.lastPathComponent, "associations.json")
        XCTAssertEqual(directory.luunaHostURL.lastPathComponent, "luuna-host.json")
        XCTAssertEqual(directory.associationsURL.deletingLastPathComponent().path, directory.url.path)
    }

    func testRoundTrip() throws {
        let registry = AssociationRegistry(directory: directory)
        XCTAssertEqual(try registry.load(), AppFileLoad(value: [], movedAside: nil))
        let associations = [
            ProjectAssociation(
                hubPath: "01-projects/daily-workspace/daily-workspace.md",
                checkouts: [
                    RepositoryCheckoutReference(path: "/Users/me/src/app", label: "app"),
                    RepositoryCheckoutReference(path: "/Users/me/src/app-wt"),
                ],
                luuna: LuunaProjectBinding(origin: .standard, projectID: "daily-workspace")),
            ProjectAssociation(hubPath: "01-projects/notes-only/notes-only.md"),
        ]

        try registry.save(associations)

        XCTAssertEqual(try registry.load(), AppFileLoad(value: associations, movedAside: nil))
        let text = try contents(directory.associationsURL)
        XCTAssertTrue(text.contains(#""origin" : "http://127.0.0.1:4242""#))
        XCTAssertTrue(text.contains(#""version" : 1"#))
        let mode = try FileManager.default.attributesOfItem(atPath: directory.associationsURL.path)[.posixPermissions]
        XCTAssertEqual((mode as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptFileIsMovedAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        try "{ not json".write(to: directory.associationsURL, atomically: true, encoding: .utf8)
        let registry = AssociationRegistry(directory: directory)

        let loaded = try registry.load()

        XCTAssertEqual(loaded.value, [])
        let aside = try XCTUnwrap(loaded.movedAside)
        XCTAssertTrue(aside.lastPathComponent.hasPrefix("associations.corrupt-"))
        XCTAssertEqual(try contents(aside), "{ not json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.associationsURL.path))
    }

    func testSaveMovesAsideAFileThatBecameCorruptAfterLoading() throws {
        let registry = AssociationRegistry(directory: directory)
        try registry.save([ProjectAssociation(hubPath: "01-projects/a/a.md")])
        try #"{"associations": 5}"#.write(to: directory.associationsURL, atomically: true, encoding: .utf8)

        try registry.save([ProjectAssociation(hubPath: "01-projects/b/b.md")])

        let asides = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
            .filter { $0.hasPrefix("associations.corrupt-") }
        XCTAssertEqual(asides.count, 1)
        XCTAssertEqual(try contents(directory.url.appendingPathComponent(asides[0])), #"{"associations": 5}"#)
        XCTAssertEqual(try registry.load().value.map(\.hubPath), ["01-projects/b/b.md"])
    }

    func testNewerFileIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let newer = #"{"version": 2, "associations": [], "groups": []}"#
        try newer.write(to: directory.associationsURL, atomically: true, encoding: .utf8)
        let registry = AssociationRegistry(directory: directory)

        XCTAssertThrowsError(try registry.load()) {
            XCTAssertEqual($0 as? AssociationRegistryError, .newerVersion(2))
        }
        XCTAssertThrowsError(try registry.save([]))
        XCTAssertEqual(try contents(directory.associationsURL), newer)
    }

    func testRejectsHubPathsOutsideTheVaultAndDuplicateIDs() {
        let registry = AssociationRegistry(directory: directory)
        for path in ["", "/Users/me/vault/hub.md", "~/hub.md", "../hub.md", "01-projects/../../x.md", "a//b.md"] {
            XCTAssertThrowsError(try registry.save([ProjectAssociation(hubPath: path)]), path)
        }
        let id = UUID()
        XCTAssertThrowsError(
            try registry.save([
                ProjectAssociation(id: id, hubPath: "a.md"), ProjectAssociation(id: id, hubPath: "b.md"),
            ])
        ) { XCTAssertEqual($0 as? AssociationRegistryError, .duplicateID(id)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.associationsURL.path))
    }

    func testHostAccessStoresTheOriginAndNeverAToken() throws {
        let store = LuunaHostAccessStore(directory: directory)
        XCTAssertNil(try store.load().value)
        let access = LuunaHostAccess(origin: try LuunaOrigin(validating: "http://localhost:5151"))

        try store.save(access)

        XCTAssertEqual(try store.load().value, access)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.luunaHostURL)) as? [String: Any]
        XCTAssertEqual(object?.keys.sorted(), ["origin"])

        let handEdited = #"{"origin":"http://127.0.0.1:4242","token":"pasted-secret"}"#
        try handEdited.write(to: directory.luunaHostURL, atomically: true, encoding: .utf8)
        try store.save(try XCTUnwrap(store.load().value))
        XCTAssertFalse(try contents(directory.luunaHostURL).contains("pasted-secret"))
    }

    func testHostAccessWithANonLoopbackOriginIsMovedAside() throws {
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        try #"{"origin":"https://example.com"}"#.write(to: directory.luunaHostURL, atomically: true, encoding: .utf8)
        let loaded = try LuunaHostAccessStore(directory: directory).load()
        XCTAssertNil(loaded.value)
        XCTAssertNotNil(loaded.movedAside)
    }
}
