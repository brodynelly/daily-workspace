import XCTest

@testable import DailyWorkspace

@MainActor
final class ChatServiceTests: XCTestCase {
    private var keys: FakeKeyStore!
    private var transport: FakeTransport!
    private var chat: ChatService!

    override func setUp() async throws {
        keys = FakeKeyStore()
        transport = FakeTransport()
        chat = ChatService(keyStore: keys, transport: transport)
    }

    func testMissingKeyAsksForSetupAndAddsNoTurn() async {
        chat.send("hello", model: "", note: nil)
        await chat.waitForCompletion()

        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertEqual(chat.error, "Add your OpenRouter key in Settings → AI.")
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testFailedRequestRollsBackTheTurn() async {
        keys.key = "sk-test"
        transport.reply = .failure(ChatError(message: "OpenRouter returned HTTP 401."))

        chat.send("hello", model: "", note: nil)
        await chat.waitForCompletion()

        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertEqual(chat.error, "OpenRouter returned HTTP 401.")
        XCTAssertFalse(chat.sending)
    }

    func testNoteIsSentOnlyWhenAttachedAndBlankModelMeansDefault() async {
        keys.key = "sk-test"

        chat.send("first", model: "  ", note: nil)
        await chat.waitForCompletion()
        chat.send("second", model: "openai/gpt-4o", note: "secret journal")
        await chat.waitForCompletion()

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertNil(transport.requests[0].model)
        XCTAssertEqual(transport.requests[0].messages.map(\.content), ["first"])
        XCTAssertFalse(transport.requests[0].messages.contains { $0.content.contains("secret journal") })
        XCTAssertEqual(transport.requests[1].model, "openai/gpt-4o")
        XCTAssertTrue(transport.requests[1].messages.last?.content.contains("secret journal") == true)
        XCTAssertEqual(chat.messages.map(\.role), [.user, .assistant, .user, .assistant])
    }

    func testKeyStatusTracksSaveAndRemove() throws {
        try chat.saveKey("  sk-test \n")
        XCTAssertTrue(chat.hasAPIKey)
        XCTAssertEqual(keys.key, "sk-test")

        try chat.saveKey("")
        XCTAssertFalse(chat.hasAPIKey)
    }

    func testUnreadableKeychainIsReportedNotTreatedAsMissingKey() {
        keys.readError = TestFailure("User interaction is not allowed.")

        chat.refreshKeyStatus()

        XCTAssertFalse(chat.hasAPIKey)
        XCTAssertEqual(chat.keyStatusError, "The Keychain could not be read: User interaction is not allowed.")
    }
}
