import AppKit
import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class QuickPanelAIPopupTests: XCTestCase {
    func testCommandJOpensPopupWithLayeredKeys() {
        let model = AppModel(dependencies: .test())
        let panel = QuickPanelController()
        panel.model = model
        XCTAssertTrue(panel.handleKey(keyCode: 38, characters: "j", modifiers: .command))
        XCTAssertTrue(panel.aiPopup.isVisible)
        // Typing belongs to the chat field, including vim letters.
        XCTAssertFalse(panel.handleKey(keyCode: 40, characters: "k"))
        XCTAssertTrue(panel.handleKey(keyCode: 40, characters: "k", modifiers: .command))
        XCTAssertEqual(panel.aiPopup.layer, .actions)
        XCTAssertFalse(panel.palette.isVisible, "⌘K inside the popup opens its own actions")
        XCTAssertTrue(panel.handleKey(keyCode: 31, characters: "z"))
        XCTAssertTrue(panel.handleKey(keyCode: 31, characters: "o"))
        XCTAssertEqual(panel.aiPopup.listQuery, "zo")
        XCTAssertEqual(panel.aiFilteredActions.map(\.id), ["zoomIn", "zoomOut"])
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertEqual(panel.aiPopup.layer, .chat)

        XCTAssertTrue(panel.handleKey(keyCode: 46, characters: "m", modifiers: [.command, .shift]))
        XCTAssertEqual(panel.aiPopup.layer, .models)
        XCTAssertEqual(panel.aiPopup.modelsStatus, "Turn on the Assistant in Settings → AI to list models")
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertFalse(panel.aiPopup.isVisible)
    }

    func testSlashCommandsFilterAndRun() {
        let model = AppModel(dependencies: .test())
        let panel = QuickPanelController()
        panel.model = model
        panel.toggleAIPopup()
        model.navigation.assistantDraft = "/zoom"
        XCTAssertEqual(panel.aiSlashActions.map(\.id), ["slash:zoom-in", "slash:zoom-out"])
        XCTAssertTrue(panel.handleKey(keyCode: 36))
        XCTAssertEqual(model.navigation.assistantDraft, "")
        XCTAssertEqual(panel.aiZoomScale, 1.1)
    }

    func testZoomIsPerViewAndSaved() {
        let model = AppModel(dependencies: .test())
        let panel = QuickPanelController()
        panel.model = model
        panel.navigate(to: .monitor)
        XCTAssertTrue(panel.handleKey(keyCode: 24, characters: "=", modifiers: .command))
        XCTAssertTrue(panel.handleKey(keyCode: 24, characters: "=", modifiers: .command))
        XCTAssertEqual(panel.zoomScale, 1.25)
        panel.navigate(to: .files)
        XCTAssertEqual(panel.zoomScale, 1)
        XCTAssertTrue(panel.handleKey(keyCode: 27, characters: "-", modifiers: .command))
        XCTAssertEqual(model.preferences.quickPanelZoom, ["monitor": 1.25, "files": 0.9])
        XCTAssertTrue(panel.handleKey(keyCode: 29, characters: "0", modifiers: .command))
        XCTAssertNil(model.preferences.quickPanelZoom["files"])
    }

    func testModelCatalogParsesBothProviders() throws {
        let anthropic = Data(#"{"data":[{"id":"claude-opus-5-5","display_name":"Claude Opus 5.5"}]}"#.utf8)
        XCTAssertEqual(
            try QuickPanelModelCatalog.parse(anthropic, provider: .anthropic),
            [.init(id: "claude-opus-5-5", name: "Claude Opus 5.5")])
        let router = Data(#"{"data":[{"id":"z/b","name":"B"},{"id":"a/a","name":"A"},{"name":"no id"}]}"#.utf8)
        XCTAssertEqual(try QuickPanelModelCatalog.parse(router, provider: .openRouter).map(\.id), ["a/a", "z/b"])
        let request = QuickPanelModelCatalog.request(provider: .anthropic, key: "k")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertEqual(request.url?.host, "api.anthropic.com")
    }

    func testMarkdownBlocks() {
        let blocks = QuickPanelMarkdownBlock.parse(
            """
            ## Sources
            Intro **bold**
            continues here.

            - **Calendar** — events
              - nested
            2. second
            > quote
            ```swift
            let x = 1
            ```
            ---
            """)
        XCTAssertEqual(
            blocks,
            [
                .heading(level: 2, text: "Sources"), .paragraph("Intro **bold** continues here."),
                .bullet(indent: 0, text: "**Calendar** — events"), .bullet(indent: 1, text: "nested"),
                .numbered(indent: 0, number: "2", text: "second"), .quote("quote"),
                .code(language: "swift", text: "let x = 1"), .rule,
            ])
    }

    func testControlHJKLMovesBetweenAISections() {
        let model = AppModel(dependencies: .test())
        let panel = QuickPanelController()
        panel.model = model
        panel.toggleAIPopup()
        XCTAssertEqual(panel.aiPopup.section, .ask)
        XCTAssertTrue(panel.handleKey(keyCode: 4, characters: "h", modifiers: .control))
        XCTAssertEqual(panel.aiPopup.section, .questions)
        XCTAssertTrue(panel.handleKey(keyCode: 37, characters: "l", modifiers: .control))
        XCTAssertEqual(panel.aiPopup.section, .conversation)
        XCTAssertTrue(panel.handleKey(keyCode: 38, characters: "j", modifiers: .control))
        XCTAssertEqual(panel.aiPopup.section, .ask)
        XCTAssertTrue(panel.handleKey(keyCode: 40, characters: "k", modifiers: .control))
        XCTAssertEqual(panel.aiPopup.section, .conversation)
        XCTAssertTrue(panel.handleKey(keyCode: 38, characters: "j"), "j reads, it does not type, outside ASK")
        XCTAssertEqual(model.navigation.assistantDraft, "")
        XCTAssertTrue(panel.handleKey(keyCode: 4, characters: "H", modifiers: .shift))
        XCTAssertEqual(panel.aiPopup.section, .ask)
        XCTAssertEqual(model.navigation.assistantDraft, "H", "Other letters start a question in ASK")
    }
}
