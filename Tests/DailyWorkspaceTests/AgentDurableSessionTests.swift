import DailyCore
import XCTest

@testable import DailyWorkspace

/// Records what the write and memory tools asked for.
final class FakeAgentWorkspace: AgentWorkspace, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [VaultChangeRequest] = []
    private var memoryCalls: [AgentMemoryCommand] = []

    var requests: [VaultChangeRequest] { lock.withLock { recorded } }
    var memoryCommands: [AgentMemoryCommand] { lock.withLock { memoryCalls } }

    func propose(_ request: VaultChangeRequest, summary: String, run: AgentRunContext) async throws
        -> VaultChangeOutcome
    {
        lock.withLock { recorded.append(request) }
        return VaultChangeOutcome(
            changeID: "c1", status: .awaitingReview, path: request.path, linesAdded: 1, linesRemoved: 0,
            note: "Queued for review.")
    }

    func memory(_ command: AgentMemoryCommand) async throws -> String {
        lock.withLock { memoryCalls.append(command) }
        return "Directory: /memories\n(empty)"
    }
}

@MainActor
final class AgentDurableSessionTests: XCTestCase {
    private func makeSession(_ transport: FakeAgentTransport) -> AssistantSession {
        let keys = FakeKeyStore()
        keys.key = "sk-ant-test"
        return AssistantSession(
            transport: transport, keyStore: keys, context: FakeAssistantContext(),
            configuration: AssistantTestClock.configuration, isEnabled: true)
    }

    private var writingLimits: AgentRuntimeLimits {
        AgentRuntimeLimits(AssistantRuntimeSettings(), agent: AgentSettings())
    }

    func testWriteToolsAreOfferedOnlyWithAWorkspace() {
        let session = makeSession(FakeAgentTransport())
        let readOnlyPrompt = JSONValue.array(session.system).encoded()
        session.applyRuntime(writingLimits)
        XCTAssertEqual(session.configuration.enabledTools, Set(AssistantTool.readOnly), "no workspace, no writes")
        XCTAssertEqual(session.configuration.capabilities, .readOnly)

        session.setWorkspace(FakeAgentWorkspace())
        session.applyRuntime(writingLimits)
        XCTAssertTrue(session.configuration.enabledTools.isSuperset(of: AssistantTool.vaultWrite + [.memory]))
        let names = session.tools.compactMap { $0["name"]?.stringValue }
        XCTAssertTrue(names.contains("create_note"))
        XCTAssertTrue(names.contains("memory"))
        XCTAssertNotEqual(JSONValue.array(session.system).encoded(), readOnlyPrompt)

        var runtime = AssistantRuntimeSettings()
        runtime.disabledTools = ["edit_note", "memory"]
        session.applyRuntime(AgentRuntimeLimits(runtime, agent: AgentSettings()))
        XCTAssertFalse(session.configuration.enabledTools.contains(.editNote))
        XCTAssertFalse(session.configuration.capabilities.memory)
    }

    func testACreateNoteCallReachesTheWorkspaceAndTheModelHearsTheOutcome() async throws {
        let transport = FakeAgentTransport([
            .success(
                agentResponse(
                    [toolCall("t1", "create_note", #"{"path":"00-inbox/idea.md","text":"An idea","summary":"why"}"#)],
                    stop: "tool_use")),
            .success(agentResponse([.text("Queued 00-inbox/idea.md for review.")], stop: "end_turn")),
        ])
        let session = makeSession(transport)
        let workspace = FakeAgentWorkspace()
        session.setWorkspace(workspace)
        session.applyRuntime(writingLimits)
        session.send("Save this idea")
        await session.waitForCompletion()

        XCTAssertNil(session.error)
        XCTAssertEqual(workspace.requests, [.create(path: "00-inbox/idea.md", text: "An idea")])
        let result = try XCTUnwrap(transport.requests.last?.messages.last?.content.first)
        XCTAssertTrue(utf8Text(result).contains("awaiting_review"))
        XCTAssertEqual(session.turns.first?.toolCalls.first?.citations.first?.value, "00-inbox/idea.md")
    }

    func testTheMemoryToolParsesAnthropicsCommands() async throws {
        let transport = FakeAgentTransport([
            .success(
                agentResponse(
                    [toolCall("t1", "memory", #"{"command":"view","path":"/memories","view_start":2,"view_end":4}"#)],
                    stop: "tool_use")),
            .success(agentResponse([.text("Nothing saved yet.")], stop: "end_turn")),
        ])
        let session = makeSession(transport)
        let workspace = FakeAgentWorkspace()
        session.setWorkspace(workspace, memoryIndex: { "- /memories/prefs.md (10 bytes)" })
        session.applyRuntime(writingLimits)
        session.send("What do you remember?")
        await session.waitForCompletion()

        XCTAssertEqual(workspace.memoryCommands, [.view(path: "/memories", range: 2...4)])
        let opening = try XCTUnwrap(transport.requests.first?.messages.first?.content)
        XCTAssertTrue(opening.contains { utf8Text($0).contains("/memories/prefs.md") }, "the index rides along")
    }

    func testEachQuestionIsSavedWhileRunningAndAgainWhenAnswered() async {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Hi.")], stop: "end_turn"))])
        let session = makeSession(transport)
        var saved: [(turns: Int, running: String?)] = []
        session.onSave = { conversation, running in saved.append((conversation.turns.count, running)) }
        session.send("Hello")
        await session.waitForCompletion()

        XCTAssertEqual(saved.map(\.turns), [0, 1])
        XCTAssertEqual(saved.map(\.running), ["Hello", nil])
    }

    func testARestoredConversationReplaysOnlyIntoTheSameContext() async throws {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Hi.")], stop: "end_turn"))])
        let session = makeSession(transport)
        session.startNewConversation(vaultAgents: nil, identity: "vault-a")
        session.send("Hello")
        await session.waitForCompletion()
        let conversation = try XCTUnwrap(session.archivedConversation())

        session.clear()
        XCTAssertTrue(session.restore(conversation))
        XCTAssertEqual(session.conversationID, conversation.id)
        XCTAssertEqual(session.transcript.count, conversation.transcript.count)

        session.startNewConversation(vaultAgents: nil, identity: "vault-b")
        XCTAssertFalse(session.restore(conversation))
        XCTAssertTrue(session.transcript.isEmpty, "another vault's transcript is never replayed")
        XCTAssertEqual(session.turns.count, 1, "its answers still show")
    }

    // MARK: Archive

    private func makeArchive(_ folder: URL, keys: FakeKeyStore, now: Date = Date()) -> ConversationArchive {
        ConversationArchive(folder: folder, keyStore: keys, isEnabled: { true }, retentionDays: { 30 }, now: { now })
    }

    func testSavedConversationsAreEncryptedAndSurviveARestart() async throws {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Secret answer.")], stop: "end_turn"))])
        let session = makeSession(transport)
        session.send("Private question")
        await session.waitForCompletion()
        let conversation = try XCTUnwrap(session.archivedConversation())

        let folder = try makeTemporaryVault(self)
        let keys = FakeKeyStore()
        makeArchive(folder, keys: keys).save(conversation)
        let file = folder.appendingPathComponent("\(conversation.id.uuidString).chat")
        let sealed = try Data(contentsOf: file)
        XCTAssertNil(sealed.range(of: Data("Private question".utf8)))
        XCTAssertNotNil(keys.key, "the key lives in the Keychain")

        let reopened = makeArchive(folder, keys: keys)
        reopened.load()
        let loaded = try XCTUnwrap(reopened.conversation(conversation.id))
        XCTAssertEqual(loaded.turns, conversation.turns)
        XCTAssertEqual(loaded.transcript, conversation.transcript, "thinking blocks replay byte-for-byte")
        XCTAssertEqual(loaded.contextFingerprint, conversation.contextFingerprint)

        let lostKey = makeArchive(folder, keys: FakeKeyStore())
        lostKey.load()
        XCTAssertEqual(lostKey.unreadable, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "an unreadable file is left in place")

        let later = makeArchive(folder, keys: keys, now: Date().addingTimeInterval(31 * 86_400))
        later.load()
        XCTAssertTrue(later.conversations.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "past retention it is deleted")
    }

    func testDeleteAllRemovesFilesAndTheKey() async throws {
        let transport = FakeAgentTransport([.success(agentResponse([.text("Hi.")], stop: "end_turn"))])
        let session = makeSession(transport)
        session.send("Hello")
        await session.waitForCompletion()
        let folder = try makeTemporaryVault(self)
        let keys = FakeKeyStore()
        let archive = makeArchive(folder, keys: keys)
        archive.save(try XCTUnwrap(session.archivedConversation()))
        XCTAssertEqual(archive.conversations.count, 1)
        archive.deleteAll()
        XCTAssertTrue(archive.conversations.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        XCTAssertEqual(keys.key ?? "", "")
    }

    // MARK: Routines

    func testARoutineRunsInItsOwnSessionAndRecordsTheOutcome() async throws {
        let folder = try makeTemporaryVault(self)
        let store = RoutineStore(url: folder.appendingPathComponent("routines.json"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = start
        let scheduler = RoutineScheduler(store: store, isEnabled: { true }, now: { clock })
        let transport = FakeAgentTransport([.success(agentResponse([.text("Filed two notes.")], stop: "end_turn"))])
        var origins: [String] = []
        let main = makeSession(transport)
        scheduler.makeSession = { origin in
            origins.append(origin)
            return main.makeSibling(origin: origin)
        }
        let routine = try XCTUnwrap(
            scheduler.add(
                name: "Inbox sweep", prompt: "Sort the inbox",
                schedule: RoutineSchedule(kind: .interval, intervalHours: 1)))
        scheduler.tick()
        XCTAssertTrue(transport.requests.isEmpty, "not due yet")

        clock = start.addingTimeInterval(3_700)
        scheduler.tick()
        XCTAssertEqual(scheduler.running, routine.id)
        for _ in 0..<200 where scheduler.running != nil { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(origins, ["routine: Inbox sweep"])
        let saved = try XCTUnwrap(try store.load().first)
        XCTAssertEqual(saved.lastOutcome, "answered")
        XCTAssertEqual(saved.lastRunAt, clock)
        XCTAssertNotNil(saved.lastConversationID)
        XCTAssertTrue(main.turns.isEmpty, "the open chat is not disturbed")
        let question = try XCTUnwrap(transport.requests.first?.messages.first?.content.last)
        XCTAssertTrue(utf8Text(question).contains("Sort the inbox"))
        XCTAssertTrue(utf8Text(question).contains("while Brody"))
    }

    func testARoutineWithoutASessionRecordsWhyAndDoesNotRetryEveryMinute() throws {
        let folder = try makeTemporaryVault(self)
        let store = RoutineStore(url: folder.appendingPathComponent("routines.json"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = start
        let scheduler = RoutineScheduler(store: store, isEnabled: { true }, now: { clock })
        scheduler.makeSession = { _ in nil }
        let routine = try XCTUnwrap(
            scheduler.add(name: "Brief", prompt: "Brief me", schedule: RoutineSchedule(kind: .interval)))
        clock = start.addingTimeInterval(5 * 3_600)
        scheduler.tick()
        XCTAssertNil(scheduler.running)
        let saved = try XCTUnwrap(scheduler.routines.first { $0.id == routine.id })
        XCTAssertEqual(saved.lastRunAt, clock)
        XCTAssertNotEqual(saved.lastOutcome, "answered")
        XCTAssertFalse(saved.isDue(at: clock.addingTimeInterval(60)))
    }
}
