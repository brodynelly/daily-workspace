import XCTest

@testable import DailyCore

final class ShortcutSettingsTests: XCTestCase {
    func testBindingsAndExplicitUnboundSurviveRoundTrip() throws {
        let first = ShortcutStroke("g")
        let second = ShortcutStroke("t", modifiers: .shift)
        let overrides = [
            "go.today": ShortcutOverride(ShortcutBinding(first, second)),
            "searchNotes": ShortcutOverride(nil),
        ]
        let original = WorkspaceSettings(dailyFolder: "notes", shortcutOverrides: overrides)
        let decoded = try JSONDecoder().decode(WorkspaceSettings.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.shortcutOverrides["go.today"]?.binding?.strokes, [first, second])
        XCTAssertNotNil(decoded.shortcutOverrides["searchNotes"])
        XCTAssertNil(decoded.shortcutOverrides["searchNotes"]?.binding)
    }

    func testMalformedEntriesDoNotDiscardOtherSettingsOrValidBindings() throws {
        let json = """
            {"dailyFolder":"safe", "mailEnabled":true, "shortcutOverrides":{
              "saveNote":{"binding":{"strokes":[{"key":"j","modifiers":1}]}},
              "broken":{"binding":{"strokes":[]}},
              "missing":{}, "wrong":42,
              "openTodayNote":{"binding":null}
            }}
            """
        let settings = try JSONDecoder().decode(WorkspaceSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.dailyFolder, "safe")
        XCTAssertTrue(settings.mailEnabled)
        XCTAssertEqual(
            settings.shortcutOverrides["saveNote"]?.binding?.strokes, [ShortcutStroke("j", modifiers: .command)])
        XCTAssertNil(settings.shortcutOverrides["broken"])
        XCTAssertNil(settings.shortcutOverrides["missing"])
        XCTAssertNil(settings.shortcutOverrides["wrong"])
        XCTAssertNotNil(settings.shortcutOverrides["openTodayNote"])
    }

    func testMalformedOverrideContainerKeepsSettingsAndDefaults() throws {
        let json = #"{"dailyFolder":"safe", "shortcutOverrides":["invalid"]}"#
        let settings = try JSONDecoder().decode(WorkspaceSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.dailyFolder, "safe")
        XCTAssertTrue(settings.shortcutOverrides.isEmpty)
    }
}
