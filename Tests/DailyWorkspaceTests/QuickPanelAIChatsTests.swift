import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class QuickPanelAIChatsTests: XCTestCase {
    private func makePanel(answers: Int) -> (QuickPanelController, AppModel) {
        let keys = FakeKeyStore()
        keys.key = "sk-ant-test"
        let transport = FakeAgentTransport(
            (0..<answers).map { .success(agentResponse([.text("Answer \($0 + 1).")], stop: "end_turn")) })
        let model = AppModel(
            dependencies: .test(agentTransport: transport, assistantKeys: keys) { $0.assistantEnabled = true })
        let panel = QuickPanelController()
        panel.model = model
        return (panel, model)
    }

    func testOpeningAIPageFilesThePreviousChatAndStepsBetweenChats() async throws {
        let (panel, model) = makePanel(answers: 2)
        model.assistant.send("First question")
        await model.assistant.waitForCompletion()
        XCTAssertEqual(model.assistant.turns.count, 1)

        panel.toggleAIPopup()
        XCTAssertTrue(model.assistant.turns.isEmpty, "The AI page opens on a fresh chat")
        XCTAssertEqual(panel.aiPopup.chats.map(\.title), ["First question"])

        model.assistant.send("Second question")
        await model.assistant.waitForCompletion()
        XCTAssertTrue(panel.handleKey(keyCode: 33, characters: "[", modifiers: .command))
        XCTAssertEqual(model.assistant.turns.first?.question, "First question")
        XCTAssertFalse(model.assistant.transcript.isEmpty, "Same model: the context is replayed unchanged")
        XCTAssertEqual(panel.aiPopup.chats.map(\.title), ["Second question"])

        XCTAssertTrue(panel.handleKey(keyCode: 30, characters: "]", modifiers: .command))
        XCTAssertEqual(model.assistant.turns.first?.question, "Second question")
    }

    func testChatsPaneOpensAndRemovesEarlierChats() async throws {
        let (panel, model) = makePanel(answers: 1)
        model.assistant.send("Old question")
        await model.assistant.waitForCompletion()
        panel.toggleAIPopup()
        XCTAssertTrue(panel.handleKey(keyCode: 4, characters: "h", modifiers: .control))
        XCTAssertEqual(panel.aiPopup.section, .chats)
        XCTAssertTrue(panel.handleKey(keyCode: 38, characters: "j"))
        XCTAssertEqual(panel.aiPopup.chatIndex, 1)
        XCTAssertTrue(panel.handleKey(keyCode: 36))
        XCTAssertEqual(model.assistant.turns.first?.question, "Old question")
        XCTAssertEqual(panel.aiPopup.section, .conversation)
        XCTAssertTrue(panel.aiPopup.chats.isEmpty, "The empty fresh chat is not filed")

        XCTAssertTrue(panel.handleKey(keyCode: 45, characters: "n", modifiers: .command))
        XCTAssertEqual(panel.aiPopup.chats.count, 1)
        panel.aiPopup.section = .chats
        panel.aiPopup.chatIndex = 1
        XCTAssertTrue(panel.handleKey(keyCode: 7, characters: "x"))
        XCTAssertTrue(panel.aiPopup.chats.isEmpty)
    }

    func testRestoreAfterModelChangeShowsAnswersWithoutReplayingContext() async throws {
        let (_, model) = makePanel(answers: 1)
        model.assistant.send("Question")
        await model.assistant.waitForCompletion()
        let chat = try XCTUnwrap(model.assistant.archivedConversation())
        model.assistant.setModel("claude-other")
        XCTAssertFalse(model.assistant.restore(chat))
        XCTAssertEqual(model.assistant.turns.count, 1)
        XCTAssertTrue(model.assistant.transcript.isEmpty)
    }
}
