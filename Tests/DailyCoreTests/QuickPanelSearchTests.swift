import XCTest

@testable import DailyCore

final class QuickPanelSearchTests: XCTestCase {
    func testAndTokensSearchAllSixRowFieldsWithoutDependingOnOrderOrCase() {
        let row = QuickPanelSearch.Row(
            title: "Résumé", detail: "Café", group: "Projects", badge: "READY",
            keys: "⌘K", keywords: "launch workspace")
        for field in ["resume", "cafe", "projects", "ready", "⌘k", "workspace"] {
            XCTAssertTrue(QuickPanelSearch.Query(field).matches(row), field)
        }
        XCTAssertTrue(QuickPanelSearch.Query(" WORKSPACE\nréSUMé  caFE ").matches(row))
        XCTAssertTrue(QuickPanelSearch.Query(" \t ").matches(row))
        XCTAssertFalse(QuickPanelSearch.Query("resume unknown").matches(row))
        XCTAssertFalse(QuickPanelSearch.Query("project ready broken").matches(row))
    }

    func testShortcutAliasesAndBareKeysMatchQAPSearchKeys() {
        let terms = QuickPanelSearch.searchKeys([["⌘T"], ["⌥⌘A", "T"]])
        XCTAssertEqual(terms.keyNames, ["t", "a", "t"])
        XCTAssertTrue(terms.keywords.contains("cmd command"))
        XCTAssertTrue(terms.keywords.contains("alt option opt"))

        let row = QuickPanelSearch.Row(title: "Open Terminal", shortcutChords: [["⌘T"], ["⌥⌘A", "T"]])
        for alias in ["cmd t", "command t", "alt a", "option a", "opt a", "⌘t", "⌥⌘a"] {
            XCTAssertTrue(QuickPanelSearch.Query(alias).matches(row), alias)
        }
        XCTAssertFalse(QuickPanelSearch.Query("control t").matches(row))
    }

    func testEverySpecialKeyAliasIncludingBothReturnSymbolsAndArrows() {
        let samples: [(String, [String])] = [
            ("⌃R", ["ctrl", "control"]), ("⇧R", ["shift"]),
            ("↩", ["return", "enter"]), ("↵", ["return", "enter"]),
            ("⇥", ["tab"]), ("␣", ["space", "leader"]),
            ("⌫", ["backspace"]), ("⌦", ["delete"]),
            ("↑", ["up"]), ("↓", ["down"]), ("←", ["left"]), ("→", ["right"]),
        ]
        for (key, aliases) in samples {
            let row = QuickPanelSearch.Row(title: "Shortcut", shortcutChords: [[key]])
            for alias in aliases {
                XCTAssertTrue(QuickPanelSearch.Query(alias).matches(row), "\(key) should match \(alias)")
            }
            XCTAssertEqual(
                row.keyNames,
                [String(key.lowercased().drop(while: { "⌃⌥⇧⌘".contains($0) }))])
        }
        let row = QuickPanelSearch.Row(title: "Shortcut", shortcutChords: [["⇧⌘↩"]])
        XCTAssertTrue(QuickPanelSearch.Query("shift command return").matches(row))
        XCTAssertFalse(QuickPanelSearch.Query("shift command delete").matches(row))
    }

    func testOneCharacterTermsRequireExactBareKeyNamesForShortcutRows() {
        let row = QuickPanelSearch.Row(
            title: "Open Terminal", detail: "A keyboard shortcut", group: "Tools",
            keys: "⌘T", shortcutChords: [["⌘T"]])
        XCTAssertTrue(QuickPanelSearch.Query("t").matches(row))
        XCTAssertTrue(QuickPanelSearch.Query("T terminal").matches(row))
        XCTAssertFalse(QuickPanelSearch.Query("a").matches(row))  // Present in the detail.
        XCTAssertFalse(QuickPanelSearch.Query("o").matches(row))  // Present in title and aliases.
        XCTAssertFalse(QuickPanelSearch.Query("⌘").matches(row))  // Present in the key label.
        XCTAssertFalse(QuickPanelSearch.Query("command a").matches(row))

        let ordinary = QuickPanelSearch.Row(title: "Open Terminal")
        XCTAssertTrue(QuickPanelSearch.Query("o").matches(ordinary))
        XCTAssertFalse(QuickPanelSearch.Query("z").matches(ordinary))
        let precomputed = QuickPanelSearch.Row(title: "Open", keywords: "cmd command", keyNames: ["T"])
        XCTAssertTrue(QuickPanelSearch.Query("t").matches(precomputed))
        XCTAssertFalse(QuickPanelSearch.Query("o").matches(precomputed))
    }

    func testFilteringRowsKeepsOnlyMatchingEntriesInSourceOrder() {
        let rows = [
            QuickPanelSearch.Row(title: "Open Terminal", group: "Tools", shortcutChords: [["⌘T"]]),
            QuickPanelSearch.Row(title: "Open Terminal", group: "Tools", shortcutChords: [["⌘A"]]),
            QuickPanelSearch.Row(title: "Toggle Terminal", group: "Tools", shortcutChords: [["⌥T"]]),
            QuickPanelSearch.Row(title: "Open Editor", group: "Tools", shortcutChords: [["⌘T"]]),
        ]
        let query = QuickPanelSearch.Query("command terminal t")
        XCTAssertEqual(rows.filter(query.matches).map(\.title), ["Open Terminal"])
    }
}
