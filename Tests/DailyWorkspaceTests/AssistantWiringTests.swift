import DailyCore
import XCTest

@testable import DailyWorkspace

/// The Assistant over the app's real sources: the vault policy before any read, verbatim statuses, the enable
/// gate, the restart ledger round trip and the AI settings. No live API calls: the transport is a fake.
@MainActor
final class AssistantWiringTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = try makeTemporaryVault(self)
    }

    private func makeModel(
        transport: FakeAgentTransport = FakeAgentTransport(), keys: FakeKeyStore = FakeKeyStore(),
        enabled: Bool = false
    ) -> AppModel {
        AppModel(
            dependencies: .test(agentTransport: transport, assistantKeys: keys) {
                $0.assistantEnabled = enabled
            })
    }

    private func vaultContext(_ model: AppModel) throws -> WorkspaceAssistantContext {
        model.useVault(at: root)
        XCTAssertNotNil(model.vaultSession.vault, "\(model.vaultSession.state)")
        return model.assistantContext
    }

    private func refusal(_ work: () async throws -> Void) async -> String? {
        do {
            try await work()
            return nil
        } catch {
            return (error as? ToolFailure)?.message ?? "unexpected \(error)"
        }
    }

    // MARK: read_note

    func testReadNoteRefusesExcludedPathsWithoutReadingThem() async throws {
        let excluded = [
            "04-archive/old.md", "templates/daily.md", "00-inbox/automation/run.md", "00-inbox/remarkable/scan.md",
            "_private/secret.md", ".obsidian/workspace.md", "01-projects/nas/ops-board.md", "repo/notes.md",
        ]
        for path in excluded { try write("secret text", to: root.appendingPathComponent(path)) }
        try write("[core]\n", to: root.appendingPathComponent("repo/.git/config"))
        let context = try vaultContext(makeModel())

        for path in excluded {
            let message = await refusal { _ = try await context.readNote(path: path, maxBytes: 1_000) }
            XCTAssertNotNil(message, path)
            XCTAssertTrue(message?.contains("excluded") == true, "\(path): \(message ?? "")")
            XCTAssertFalse(message?.contains("secret text") == true, path)
        }
    }

    func testReadNoteRefusesPathsOutsideTheVault() async throws {
        let outside = try makeTemporaryVault(self)
        try write("outside text", to: outside.appendingPathComponent("elsewhere.md"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"), withDestinationURL: outside)
        let context = try vaultContext(makeModel())

        for path in ["../elsewhere.md", "/etc/hosts", "~/notes.md", "link/elsewhere.md", "a/../../elsewhere.md"] {
            let message = await refusal { _ = try await context.readNote(path: path, maxBytes: 1_000) }
            XCTAssertNotNil(message, path)
            XCTAssertFalse(message?.contains("outside text") == true, path)
        }
    }

    func testReadNoteIsBoundedByMaxBytes() async throws {
        try write("# Alpha\nShip the beta é and more.", to: root.appendingPathComponent("01-projects/alpha/hub.md"))
        let context = try vaultContext(makeModel())

        let whole = try await context.readNote(path: "01-projects/alpha/hub.md", maxBytes: 1_000)
        XCTAssertEqual(whole.text, "# Alpha\nShip the beta é and more.")
        XCTAssertFalse(whole.truncated)

        // 23 bytes ends inside "é" (2 bytes): the partial character is dropped, never decoded as garbage.
        let cut = try await context.readNote(path: "01-projects/alpha/../alpha/hub.md", maxBytes: 23)
        XCTAssertEqual(cut.path, "01-projects/alpha/hub.md")
        XCTAssertEqual(cut.text, "# Alpha\nShip the beta ")
        XCTAssertTrue(cut.truncated)
    }

    // MARK: search_notes

    func testSearchNotesSkipsExcludedFolders() async throws {
        try write("The zebra plan.", to: root.appendingPathComponent("01-projects/alpha/zebra.md"))
        try write("A zebra note.", to: root.appendingPathComponent("02-areas/notes.md"))
        for path in ["04-archive/zebra.md", "templates/zebra.md", "_drafts/zebra.md", "01-projects/zebra-board.md"] {
            try write("zebra", to: root.appendingPathComponent(path))
        }
        let context = try vaultContext(makeModel())

        let hits = try await context.searchNotes(query: "zebra", limit: 10)
        XCTAssertEqual(hits.map(\.path), ["01-projects/alpha/zebra.md", "02-areas/notes.md"])
        XCTAssertEqual(hits.first?.snippet, "The zebra plan.")

        // The index is cached until a refresh, then rebuilt.
        try write("zebra again", to: root.appendingPathComponent("03-resources/new.md"))
        let cached = try await context.searchNotes(query: "zebra", limit: 10)
        XCTAssertEqual(cached.count, 2)
        context.invalidateNotes()
        let rebuilt = try await context.searchNotes(query: "zebra", limit: 10)
        XCTAssertEqual(rebuilt.count, 3)
    }

    // MARK: list_open_loops

    func testOpenLoopsKeepTheNativeStatusVerbatimWithIDsAndPaths() async throws {
        try LoopVaultFixture.populate(root)
        let model = makeModel()
        let context = try vaultContext(model)
        // The vault change starts its own refresh, which supersedes an explicit one; wait for the files.
        await model.openLoops.refresh()
        for _ in 0..<200 where model.openLoops.observations[.org] == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        let org = try await context.openLoops(source: "org", project: nil, status: nil)
        XCTAssertEqual(org.map(\.status), ["TODO", "NEXT", "DONE"])
        XCTAssertTrue(org.allSatisfy { $0.id.hasPrefix("org:") && $0.path == "org/inbox.org" })

        let seeds = try await context.openLoops(source: "seeds", project: "x", status: nil)
        XCTAssertEqual(seeds.map(\.status), ["in_progress"])
        XCTAssertEqual(seeds.first?.id, "seeds:brain-a1")
        XCTAssertEqual(seeds.first?.path, ".seeds/issues.jsonl")

        let next = try await context.openLoops(source: nil, project: nil, status: "next")
        XCTAssertEqual(next.map(\.title), ["Draft the proposal"])
        XCTAssertEqual(next.first?.status, "NEXT")
    }

    func testAnUnreadableSourceIsReportedNotEmpty() async throws {
        let model = makeModel()
        let context = try vaultContext(model)
        // An empty vault has no `.seeds/`: unread or uninitialized, never "nothing to do".
        let seeds = await context.unreadableLoopSources()["seeds"]
        XCTAssertNotNil(seeds)
        let message = await refusal { _ = try await context.openLoops(source: "plot", project: nil, status: nil) }
        XCTAssertTrue(message?.contains("unknown, not empty") == true, message ?? "")
    }

    // MARK: Gating

    func testNothingIsSentWhileTheAssistantIsDisabled() async throws {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Hi.")], stop: "end_turn"))])
        let keys = FakeKeyStore()
        keys.key = "sk-ant-test"
        let model = makeModel(transport: transport, keys: keys, enabled: false)

        model.assistant.send("What's due today?")
        await model.assistant.waitForCompletion()
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(model.assistant.error, AssistantSession.disabledMessage)
        do {
            _ = try await model.assistant.draftRestartRecord(project: "alpha")
            XCTFail("A draft must not be requested while disabled")
        } catch {
            XCTAssertEqual((error as? AgentError)?.kind, .disabled)
        }
        XCTAssertTrue(transport.requests.isEmpty)

        model.preferences.assistantEnabled = true
        model.assistant.send("What's due today?")
        await model.assistant.waitForCompletion()
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(model.assistant.turns.map(\.answer), ["Hi."])
    }

    func testTheVaultAgentsFileIsSentAndAChangeStartsANewConversation() async throws {
        try write("# Vault rules\nNever write to the root.", to: root.appendingPathComponent("AGENTS.md"))
        let transport = FakeAgentTransport()
        transport.whenScriptEnds = { _ in .success(agentResponse([.text("Ok.")], stop: "end_turn")) }
        let keys = FakeKeyStore()
        keys.key = "sk-ant-test"
        let model = makeModel(transport: transport, keys: keys, enabled: true)
        model.useVault(at: root)

        model.assistant.send("Hello")
        await model.assistant.waitForCompletion()
        let system = transport.bodies.first?["system"] as? [[String: Any]] ?? []
        XCTAssertTrue(system.contains { ($0["text"] as? String)?.contains("Never write to the root.") == true })

        model.syncAssistantVaultAgents()
        XCTAssertEqual(model.assistant.turns.count, 1, "An unchanged AGENTS.md keeps the conversation")
        try write("# Vault rules\nChanged.", to: root.appendingPathComponent("AGENTS.md"))
        model.syncAssistantVaultAgents()
        XCTAssertTrue(model.assistant.turns.isEmpty)
        XCTAssertTrue(JSONValue.array(model.assistant.system).encoded().containsBytes(Data("Changed.".utf8)))
    }

    // MARK: Restart records

    private func draft(sources: [String], observed: Set<String>) throws -> RestartDraft {
        let list = sources.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
            {"decision":"Ship the hub index.","next_action":"Run swift test.","notes":"","sources_read":[\(list)]}
            """
        return try XCTUnwrap(
            RestartDraft(json: json, projectSlug: "alpha", createdAt: AssistantTestClock.now, observedPaths: observed))
    }

    func testAcceptAppendsWithHashesAndDetectsChangedSources() throws {
        let note = root.appendingPathComponent("01-projects/alpha/hub.md")
        try write("# Alpha\n", to: note)
        let ledger = RestartLedger(url: try makeTemporaryVault(self).appendingPathComponent("restart-ledger.jsonl"))
        let recorder = RestartRecorder(ledger: ledger, vaultRoot: root)
        let accepted = AssistantTestClock.now.addingTimeInterval(60)

        let saved = try recorder.accept(
            draft(sources: ["01-projects/alpha/hub.md"], observed: ["01-projects/alpha/hub.md"]), at: accepted)
        XCTAssertEqual(saved.skippedLines, [])
        XCTAssertEqual(saved.record.sources.map(\.path), ["01-projects/alpha/hub.md"])
        XCTAssertEqual(saved.record.sources.first?.sha256, RestartLedger.sha256(of: Data("# Alpha\n".utf8)))
        XCTAssertEqual(saved.record.acceptedAt, accepted)
        XCTAssertEqual(try ledger.records(project: "alpha").latest, saved.record)

        XCTAssertEqual(try recorder.latest(project: "alpha").checks["01-projects/alpha/hub.md"], .unchanged)
        try write("# Alpha, edited\n", to: note)
        XCTAssertEqual(try recorder.latest(project: "alpha").checks["01-projects/alpha/hub.md"], .changed)
        try FileManager.default.removeItem(at: note)
        XCTAssertEqual(try recorder.latest(project: "alpha").checks["01-projects/alpha/hub.md"], .missing)
    }

    func testAcceptRefusesSourcesOutsideTheVaultAndAppendsNothing() throws {
        try write("old", to: root.appendingPathComponent("04-archive/old.md"))
        let ledger = RestartLedger(url: try makeTemporaryVault(self).appendingPathComponent("restart-ledger.jsonl"))
        let recorder = RestartRecorder(ledger: ledger, vaultRoot: root)

        for path in ["04-archive/old.md", "../outside.md", "01-projects/missing.md"] {
            XCTAssertThrowsError(try recorder.accept(draft(sources: [path], observed: []), at: Date()), path)
        }
        XCTAssertEqual(try ledger.allRecords().records, [])
    }

    func testRestartRecordsReportSavedOnlyAfterTheAppendAndSurfaceSkippedLines() async throws {
        try write("# Alpha\n", to: root.appendingPathComponent("01-projects/alpha/hub.md"))
        let directory = try makeTemporaryVault(self)
        let ledger = RestartLedger(url: directory.appendingPathComponent("restart-ledger.jsonl"))
        try write("{not json\n", to: ledger.url)
        let restarts = RestartRecords(ledger: ledger, vaultRoot: { self.root })

        let outcome = await restarts.accept(try draft(sources: ["01-projects/alpha/hub.md"], observed: []))
        guard case .saved(let record, let skipped) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(skipped, [1])
        XCTAssertEqual(restarts.revision, 1)
        // The ledger keeps milliseconds, so compare what was written by identity and content.
        let read = try ledger.records(project: "alpha").records
        XCTAssertEqual(read.map(\.id), [record.id])
        XCTAssertEqual(read.first?.sources.map(\.sha256), record.sources.map(\.sha256))
    }

    // MARK: Settings

    func testAssistantSettingsRoundTrip() throws {
        let legacy = try JSONDecoder().decode(WorkspaceSettings.self, from: Data(#"{"dailyFolder":"Daily"}"#.utf8))
        XCTAssertFalse(legacy.assistantEnabled)
        XCTAssertEqual(legacy.assistantModel, "claude-opus-5-5")
        let wrongType = try JSONDecoder().decode(
            WorkspaceSettings.self, from: Data(#"{"assistantEnabled":"yes","assistantModel":7}"#.utf8))
        XCTAssertFalse(wrongType.assistantEnabled)
        XCTAssertEqual(wrongType.assistantModel, "claude-opus-5-5")

        let store = InMemorySettings()
        let preferences = Preferences(store: store)
        XCTAssertFalse(preferences.assistantEnabled)
        preferences.assistantEnabled = true
        preferences.assistantModel = "claude-sonnet-5"
        let encoded = try JSONEncoder().encode(try XCTUnwrap(store.stored))
        let decoded = try JSONDecoder().decode(WorkspaceSettings.self, from: encoded)
        XCTAssertTrue(decoded.assistantEnabled)
        XCTAssertEqual(decoded.assistantModel, "claude-sonnet-5")

        let reloaded = Preferences(store: store)
        XCTAssertTrue(reloaded.assistantEnabled)
        XCTAssertEqual(reloaded.assistantModel, "claude-sonnet-5")
    }

    func testChangingTheModelStartsANewConversation() async {
        let transport = FakeAgentTransport()
        transport.whenScriptEnds = { _ in .success(agentResponse([.text("Ok.")], stop: "end_turn")) }
        let keys = FakeKeyStore()
        keys.key = "sk-ant-test"
        let model = makeModel(transport: transport, keys: keys, enabled: true)
        model.assistant.send("Hello")
        await model.assistant.waitForCompletion()
        XCTAssertEqual(model.assistant.turns.count, 1)

        model.assistant.setModel("claude-sonnet-5")
        XCTAssertTrue(model.assistant.turns.isEmpty)
        model.assistant.send("Hello again")
        await model.assistant.waitForCompletion()
        XCTAssertEqual(transport.bodies.last?["model"] as? String, "claude-sonnet-5")
        model.assistant.setModel("  ")
        XCTAssertEqual(model.assistant.configuration.model, AssistantSession.defaultModel)
    }

    func testAnswersThatMentionAStatusWithoutARecordIDAreUnverified() {
        let record = [ToolCitation(kind: .record, value: "org:abc")]
        let path = [ToolCitation(kind: .path, value: "01-projects/alpha/hub.md")]
        XCTAssertTrue(AnswerClaims.isUnverified(answer: "The proposal is NEXT.", citations: []))
        XCTAssertTrue(AnswerClaims.isUnverified(answer: "That task is done.", citations: path))
        XCTAssertFalse(AnswerClaims.isUnverified(answer: "The proposal is NEXT (org:abc).", citations: record))
        XCTAssertFalse(AnswerClaims.isUnverified(answer: "The hub describes the index.", citations: []))
    }
}
