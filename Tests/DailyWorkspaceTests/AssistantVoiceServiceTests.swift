import XCTest

@testable import DailyWorkspace

@MainActor
final class AssistantVoiceServiceTests: XCTestCase {
    func testVoiceStartsOffWithoutListeningOrSpeaking() {
        let voice = AssistantVoiceService()
        XCTAssertFalse(voice.isListening)
        XCTAssertFalse(voice.isRequestingPermission)
        XCTAssertFalse(voice.speaksReplies)
        XCTAssertEqual(voice.recognizedText, "")
        voice.speakAnswer("Not requested")
        XCTAssertFalse(voice.speaksReplies)
        voice.stop()
    }

    func testPartialDictationRevisesSharedDraftWithoutSubmitting() {
        let initial = "Check the calendar"
        let partial = AssistantVoiceService.draft(initial, replacing: "", with: "and next")
        XCTAssertEqual(partial, "Check the calendar and next")
        XCTAssertEqual(
            AssistantVoiceService.draft(partial, replacing: "and next", with: "and next week"),
            "Check the calendar and next week")
        XCTAssertEqual(AssistantVoiceService.draft(initial, replacing: "", with: ""), initial)
    }

    func testDisablingSpeechStopsReplyOptIn() {
        let voice = AssistantVoiceService()
        voice.setSpeaksReplies(true)
        XCTAssertTrue(voice.speaksReplies)
        voice.stop()
        XCTAssertFalse(voice.speaksReplies)
    }
}
