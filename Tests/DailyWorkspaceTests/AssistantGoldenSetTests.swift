import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

/// Scripted transport, real tool loop and real vault-backed AssistantContext. These tests do not grade a model.
@MainActor
final class AssistantGoldenSetTests: XCTestCase {
    static let hub = "01-projects/atlas/atlas.md"
    static let restart = "01-projects/atlas/notes/restart.md"
    static let run = "01-projects/atlas/notes/run.md"
    static let state = "01-projects/atlas/notes/project-state.md"
    static let olderRecordID = UUID(uuidString: "A1000000-0000-4000-8000-000000000000")!
    static let recordID = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
    static let hubHash = "a29d652df7b225645f2b3b5a74bdfe54ee7be61c2b1aa7b6db0efdf838045bf9"
    static let restartHash = "e824d5769e9db6ec66e7808c7d468fdb523342a0f5f687c93af6534620aef3cd"
    static let runHash = "d0dbf2d589eb6443e9efd561ec24cccdb61a8f86c60e0be1c96f84ea3e4a59a0"

    static let nativeTicketID = "atlas-publish-42"

    struct Lookup {
        let name: String
        let input: String
        let evidence: [String]
        let citation: ToolCitation?
        var row: Row?
        var isError = false
    }

    struct Row {
        let source: String
        let title: String
        let status: String
    }

    struct Question {
        let id: Int
        let text: String
        let lookups: [Lookup]
        let answer: String
    }

    func copyFixture(into root: URL) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vault", isDirectory: true)
        let files = FileManager.default
        let items = try XCTUnwrap(files.enumerator(at: fixture, includingPropertiesForKeys: [.isDirectoryKey]))
        for case let url as URL in items {
            let relative = String(url.path.dropFirst(fixture.path.count + 1))
            let destination = root.appendingPathComponent(relative)
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                try files.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                try files.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files.copyItem(at: url, to: destination)
            }
        }
        // Git never tracks nested .git directories; create the marker for a fresh checkout too.
        try files.createDirectory(
            at: root.appendingPathComponent("01-projects/nested/.git"), withIntermediateDirectories: true)
        XCTAssertEqual(try RestartLedger.sha256(ofFileAt: root.appendingPathComponent(Self.hub)), Self.hubHash)
        XCTAssertEqual(try RestartLedger.sha256(ofFileAt: root.appendingPathComponent(Self.restart)), Self.restartHash)
        XCTAssertEqual(try RestartLedger.sha256(ofFileAt: root.appendingPathComponent(Self.run)), Self.runHash)
    }

    func model(root: URL, appRoot: URL, calendar: FakeCalendarStore) async throws -> AppModel {
        let model = AppModel(
            dependencies: .test(
                directory: WorkspaceDirectory(url: appRoot), calendarStore: calendar))
        model.useVault(at: root)
        await model.openLoops.refresh()
        try await loadAtlasHub(in: model)
        return model
    }

    func loadAtlasHub(in model: AppModel) async throws {
        await model.projects.refresh()
        for _ in 0..<400 {
            if let hub = model.projects.hubs?.value.first(where: { $0.slug == "atlas" }) {
                XCTAssertEqual(hub.path, Self.hub)
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for the Atlas project hub")
    }

    func testExcludedSearchAndDisabledAssistantNeverSendPrivateFixtureText() async throws {
        let root = try makeTemporaryVault(self)
        try copyFixture(into: root)
        let model = try await model(root: root, appRoot: try makeTemporaryVault(self), calendar: FakeCalendarStore())
        let transport = FakeAgentTransport([
            .success(
                agentResponse(
                    [toolCall("search", "search_notes", #"{"query":"PRIVATE_","limit":25}"#)], stop: "tool_use")),
            .success(agentResponse([.text("No readable matching notes.")], stop: "end_turn")),
        ])
        let keys = FakeKeyStore()
        keys.key = "synthetic-key-never-sent-over-network"
        let disabled = AssistantSession(
            transport: transport, keyStore: keys, context: model.assistantContext, isEnabled: false)
        disabled.send("Read every private file")
        await disabled.waitForCompletion()
        XCTAssertEqual(disabled.error, AssistantSession.disabledMessage)
        XCTAssertTrue(transport.requests.isEmpty)
        disabled.setEnabled(true)
        disabled.send("Search for PRIVATE_ in accessible notes")
        await disabled.waitForCompletion()
        XCTAssertNil(disabled.error)
        XCTAssertEqual(transport.requests.count, 2)
        let result = try XCTUnwrap(transport.requests.last?.messages.last?.content.first)
        let block = try XCTUnwrap(parseJSONObject(result))
        XCTAssertEqual(block["content"] as? String, #"{"hits":[]}"#)
        XCTAssertTrue(disabled.turns.first?.citations.isEmpty == true)
        XCTAssertFalse(transport.bodies.description.contains("PRIVATE_ARCHIVE_CANARY"))
        XCTAssertFalse(transport.bodies.description.contains("PRIVATE_HIDDEN_CANARY"))
        XCTAssertFalse(transport.bodies.description.contains("PRIVATE_REPO_CANARY"))
    }

    func testOutsideVaultPathRefusedThroughToolLoop() async throws {
        let root = try makeTemporaryVault(self)
        try copyFixture(into: root)
        let model = try await model(root: root, appRoot: try makeTemporaryVault(self), calendar: FakeCalendarStore())
        let transport = FakeAgentTransport([
            .success(
                agentResponse(
                    [toolCall("outside", "read_note", #"{"path":"../outside.md","max_bytes":20000}"#)], stop: "tool_use"
                )),
            .success(agentResponse([.text("That path is outside the vault and was not read.")], stop: "end_turn")),
        ])
        let keys = FakeKeyStore()
        keys.key = "synthetic-key"
        let session = AssistantSession(transport: transport, keyStore: keys, context: model.assistantContext)
        session.send("Read ../outside.md")
        await session.waitForCompletion()
        let result = try XCTUnwrap(transport.requests.last?.messages.last?.content.first)
        let block = try XCTUnwrap(parseJSONObject(result))
        XCTAssertEqual(block["is_error"] as? Bool, true)
        XCTAssertTrue((block["content"] as? String)?.contains("outside the vault") == true)
        XCTAssertTrue(session.turns.first?.toolCalls.first?.citations.isEmpty == true)
        XCTAssertFalse(transport.bodies.description.contains("PRIVATE_"))
    }

    func testChangedRestartSourceIsDetectableWithoutChangingAcceptedHash() async throws {
        let root = try makeTemporaryVault(self)
        try copyFixture(into: root)
        let appRoot = try makeTemporaryVault(self)
        let ledger = RestartLedger(url: WorkspaceDirectory(url: appRoot).restartLedgerURL)
        let record = RestartRecord(
            id: Self.recordID, projectSlug: "atlas", createdAt: AssistantTestClock.now,
            acceptedAt: AssistantTestClock.now, decision: "Keep the index local.", nextAction: "Review indexing tests.",
            sources: [SourceRef(path: Self.hub, sha256: Self.hubHash, observedAt: AssistantTestClock.now)])
        try ledger.append(record)
        let model = try await model(root: root, appRoot: appRoot, calendar: FakeCalendarStore())
        try write("# Atlas revised\n", to: root.appendingPathComponent(Self.hub))
        let project = try await model.assistantContext.project(slug: "atlas")
        XCTAssertEqual(project.latestRestart?.sources.first?.sha256, Self.hubHash)
        XCTAssertNotEqual(try RestartLedger.sha256(ofFileAt: root.appendingPathComponent(Self.hub)), Self.hubHash)
        XCTAssertTrue(project.relatedNotes.contains(Self.restart))
    }
}
