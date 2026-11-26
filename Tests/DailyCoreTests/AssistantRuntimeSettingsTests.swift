import XCTest

@testable import DailyCore

final class AssistantRuntimeSettingsTests: XCTestCase {
    private func decode(_ json: String) throws -> AssistantRuntimeSettings {
        try JSONDecoder().decode(AssistantRuntimeSettings.self, from: Data(json.utf8))
    }

    func testMissingKeysKeepTheDefaults() throws {
        let settings = try decode("{}")
        XCTAssertEqual(settings, AssistantRuntimeSettings())
        XCTAssertEqual(settings.maxToolRounds, 8)
        XCTAssertEqual(settings.maxOutputTokens, 16_000)
        XCTAssertEqual(settings.maxRetries, 2)
        XCTAssertEqual(settings.toolTimeoutSeconds, 30)
        XCTAssertEqual(settings.maxToolResultBytes, 100_000)
        XCTAssertEqual(settings.chatEffort, "low")
        XCTAssertEqual(settings.draftEffort, "medium")
        XCTAssertEqual(settings.disabledTools, [])
    }

    func testOutOfRangeAndMistypedValuesAreClampedOrReset() throws {
        let settings = try decode(
            """
            {"maxToolRounds": 500, "maxOutputTokens": 10, "chatEffort": "turbo", "draftEffort": "high",
             "maxRetries": -3, "toolTimeoutSeconds": "soon", "maxToolResultBytes": 999999999,
             "disabledTools": [" get_agenda ", "get_agenda", "", "made_up"], "futureKey": true}
            """)
        XCTAssertEqual(settings.maxToolRounds, 20)
        XCTAssertEqual(settings.maxOutputTokens, 1_024)
        XCTAssertEqual(settings.chatEffort, "low")
        XCTAssertEqual(settings.draftEffort, "high")
        XCTAssertEqual(settings.maxRetries, 0)
        XCTAssertEqual(settings.toolTimeoutSeconds, 30)
        XCTAssertEqual(settings.maxToolResultBytes, 400_000)
        XCTAssertEqual(settings.disabledTools, ["get_agenda", "made_up"])
    }

    func testWorkspaceSettingsRoundTripTheRuntimeBlockAndSurviveAMalformedOne() throws {
        var settings = WorkspaceSettings()
        settings.assistantRuntime = AssistantRuntimeSettings(maxToolRounds: 4, disabledTools: ["read_note"])
        let data = try JSONEncoder().encode(settings)
        let loaded = try JSONDecoder().decode(WorkspaceSettings.self, from: data)
        XCTAssertEqual(loaded.assistantRuntime, settings.assistantRuntime)

        let malformed = try JSONDecoder().decode(
            WorkspaceSettings.self, from: Data(#"{"assistantRuntime": 7, "assistantModel": "m"}"#.utf8))
        XCTAssertEqual(malformed.assistantRuntime, AssistantRuntimeSettings())
        XCTAssertEqual(malformed.assistantModel, "m")

        let older = try JSONDecoder().decode(WorkspaceSettings.self, from: Data(#"{"assistantModel": "m"}"#.utf8))
        XCTAssertEqual(older.assistantRuntime, AssistantRuntimeSettings())
    }
}
