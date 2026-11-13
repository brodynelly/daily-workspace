import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
extension AssistantWiringTests {
    // MARK: Settings

    func testAssistantSettingsRoundTrip() throws {
        let legacy = try JSONDecoder().decode(WorkspaceSettings.self, from: Data(#"{"dailyFolder":"Daily"}"#.utf8))
        XCTAssertFalse(legacy.assistantEnabled)
        XCTAssertEqual(legacy.assistantModel, "claude-opus-5-5")
        XCTAssertEqual(legacy.assistantProvider, .anthropic)
        XCTAssertEqual(legacy.openRouterModel, WorkspaceSettings.defaultOpenRouterModel)
        let wrongType = try JSONDecoder().decode(
            WorkspaceSettings.self,
            from: Data(
                #"{"assistantEnabled":"yes","assistantModel":7,"assistantProvider":"unknown","openRouterModel":7}"#
                    .utf8))
        XCTAssertFalse(wrongType.assistantEnabled)
        XCTAssertEqual(wrongType.assistantModel, "claude-opus-5-5")
        XCTAssertEqual(wrongType.assistantProvider, .anthropic)
        XCTAssertEqual(wrongType.openRouterModel, WorkspaceSettings.defaultOpenRouterModel)

        let store = InMemorySettings()
        let preferences = Preferences(store: store)
        XCTAssertFalse(preferences.assistantEnabled)
        preferences.assistantEnabled = true
        preferences.assistantModel = "claude-sonnet-5"
        preferences.assistantProvider = .openRouter
        preferences.openRouterModel = "openai/gpt-4.1"
        let encoded = try JSONEncoder().encode(try XCTUnwrap(store.stored))
        let decoded = try JSONDecoder().decode(WorkspaceSettings.self, from: encoded)
        XCTAssertTrue(decoded.assistantEnabled)
        XCTAssertEqual(decoded.assistantModel, "claude-sonnet-5")
        XCTAssertEqual(decoded.assistantProvider, .openRouter)
        XCTAssertEqual(decoded.openRouterModel, "openai/gpt-4.1")

        let reloaded = Preferences(store: store)
        XCTAssertTrue(reloaded.assistantEnabled)
        XCTAssertEqual(reloaded.assistantModel, "claude-sonnet-5")
        XCTAssertEqual(reloaded.assistantProvider, .openRouter)
        XCTAssertEqual(reloaded.openRouterModel, "openai/gpt-4.1")
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

    func testProviderSwitchClearsConversationAndKeepsKeysSeparate() async {
        let anthropic = FakeAgentTransport([
            .success(agentResponse([.text("First.")], stop: "end_turn")),
            .success(agentResponse([.text("Third.")], stop: "end_turn")),
        ])
        let openRouter = FakeAgentTransport([
            .success(agentResponse([.text("Second.")], stop: "end_turn"))
        ])
        let anthropicKey = FakeKeyStore()
        anthropicKey.key = "anthropic-test"
        let openRouterKey = FakeKeyStore()
        let session = AssistantSession(
            transport: anthropic, keyStore: anthropicKey, context: FakeAssistantContext(),
            openRouterTransport: openRouter, openRouterKeyStore: openRouterKey)
        session.send("First")
        await session.waitForCompletion()
        XCTAssertEqual(session.turns.count, 1)
        session.setProvider(.openRouter, model: "openai/gpt-4.1")
        XCTAssertTrue(session.turns.isEmpty)
        session.send("No OpenRouter key")
        XCTAssertEqual(session.error, "Add your OpenRouter API key in Settings → AI.")
        XCTAssertTrue(openRouter.requests.isEmpty)
        openRouterKey.key = "router-test"
        session.send("Second")
        await session.waitForCompletion()
        XCTAssertEqual(openRouter.requests.first?.model, "openai/gpt-4.1")
        XCTAssertEqual(session.turns.count, 1)
        session.setProvider(.anthropic, model: "")
        XCTAssertTrue(session.turns.isEmpty)
        session.send("Third")
        await session.waitForCompletion()
        XCTAssertEqual(anthropic.requests.count, 2)
        XCTAssertEqual(anthropic.requests.last?.model, AssistantSession.defaultModel)
    }

    func testSelectedProviderKeyStatusDoesNotReuseOtherProviderCredential() throws {
        let anthropic = FakeKeyStore()
        anthropic.key = "anthropic-test"
        let openRouter = FakeKeyStore()
        let key = AssistantKey(store: anthropic, openRouterStore: openRouter)
        XCTAssertTrue(key.isSaved)
        key.setProvider(.openRouter)
        XCTAssertFalse(key.isSaved)
        try key.save("router-test")
        XCTAssertTrue(key.isSaved)
        XCTAssertEqual(openRouter.key, "router-test")
        XCTAssertEqual(anthropic.key, "anthropic-test")
        key.setProvider(.anthropic)
        XCTAssertTrue(key.isSaved)
    }

    func testAnswersThatMentionAStatusWithoutARecordIDAreUnverified() {
        let record = [ToolCitation(kind: .record, value: "local:abc")]
        let path = [ToolCitation(kind: .path, value: "01-projects/alpha/hub.md")]
        XCTAssertTrue(AnswerClaims.isUnverified(answer: "The proposal is completed.", citations: []))
        XCTAssertTrue(AnswerClaims.isUnverified(answer: "That task is done.", citations: path))
        XCTAssertFalse(AnswerClaims.isUnverified(answer: "The proposal is done (local:abc).", citations: record))
        XCTAssertFalse(AnswerClaims.isUnverified(answer: "The hub describes the index.", citations: []))
    }
}
