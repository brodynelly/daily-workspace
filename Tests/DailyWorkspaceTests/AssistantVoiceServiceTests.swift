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
        var draft = AssistantVoiceService.Draft()
        let initial = "Check the calendar"
        XCTAssertEqual(draft.update(initial, with: ""), initial)
        let partial = draft.update(initial, with: "and next")
        XCTAssertEqual(partial, "Check the calendar and next")
        XCTAssertEqual(draft.update(partial, with: "and next week"), "Check the calendar and next week")
    }

    func testPartialDictationPreservesTextTypedAfterRecognizedSpan() {
        var draft = AssistantVoiceService.Draft()
        let partial = draft.update("Check the calendar", with: "and next")
        let typed = partial + " then add a reminder"
        let revised = draft.update(typed, with: "and next week")
        XCTAssertEqual(revised, "Check the calendar and next week then add a reminder")
        XCTAssertEqual(
            draft.update(revised, with: "and next week's events"),
            "Check the calendar and next week's events then add a reminder")
    }

    func testPartialDictationReplacesTrackedSpanRatherThanMatchingRepeatedWords() {
        var draft = AssistantVoiceService.Draft()
        let partial = draft.update("and next", with: "and next")
        let typed = partial + " and next"
        XCTAssertEqual(draft.update(typed, with: "and next week"), "and next and next week and next")
    }

    func testPartialDictationRebasesSpanAfterTypingBeforeIt() {
        var draft = AssistantVoiceService.Draft()
        let partial = draft.update("Plan", with: "one")
        XCTAssertEqual(draft.update("Please " + partial, with: "one two"), "Please Plan one two")
    }

    func testPartialDictationDoesNotOverwriteUserEditInsideRecognizedSpan() {
        var draft = AssistantVoiceService.Draft()
        let partial = draft.update("Plan", with: "one")
        let edited = partial.replacingOccurrences(of: "one", with: "mine")
        XCTAssertEqual(draft.update(edited, with: "one two"), edited)
        XCTAssertEqual(draft.update(edited, with: "one two three"), edited)
    }

    func testDisablingSpeechStopsReplyOptIn() {
        let voice = AssistantVoiceService()
        voice.setSpeaksReplies(true)
        XCTAssertTrue(voice.speaksReplies)
        voice.stop()
        XCTAssertFalse(voice.speaksReplies)
    }
}
