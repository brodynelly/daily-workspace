import DailyCore
import XCTest

@testable import DailyWorkspace

@MainActor
final class KeyboardShortcutCatalogTests: XCTestCase {
    private func binding(_ key: String, _ modifiers: ShortcutModifiers = []) -> ShortcutBinding {
        ShortcutBinding(ShortcutStroke(key, modifiers: modifiers))
    }

    private func assertFailure(
        _ result: Result<Void, ShortcutBindingError>, _ expected: ShortcutBindingError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch result {
        case .success: XCTFail("Expected \(expected)", file: file, line: line)
        case .failure(let error): XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func testDefaultsPreserveExistingCommandsAndGoSequences() {
        let preferences = Preferences(store: InMemorySettings())
        XCTAssertEqual(
            KeyboardShortcutCatalog.binding(for: "go.today", preferences: preferences), binding("1", .command))
        XCTAssertEqual(
            KeyboardShortcutCatalog.binding(for: "goChord.today", preferences: preferences),
            ShortcutBinding(ShortcutStroke("g"), ShortcutStroke("t")))
        XCTAssertNil(KeyboardShortcutCatalog.binding(for: "chooseVault", preferences: preferences))
        XCTAssertEqual(KeyboardShortcutCatalog.label(for: "calendar.previousWeek", preferences: preferences), "⌘←")
        XCTAssertEqual(KeyboardShortcutCatalog.binding(for: "quickSearch", preferences: preferences), binding("/"))
        XCTAssertEqual(KeyboardShortcutCatalog.binding(for: "keyboardHelp", preferences: preferences), binding("f1"))
        XCTAssertEqual(KeyboardShortcutCatalog.label(for: "keyboardHelp", preferences: preferences), "F1")
        XCTAssertEqual(
            KeyboardShortcutCatalog.binding(for: "assistant.panel", preferences: preferences), binding("/", .shift))
        XCTAssertEqual(KeyboardShortcutCatalog.label(for: "assistant.panel", preferences: preferences), "?")
        XCTAssertNil(binding("/").menuShortcut)
        XCTAssertNil(binding("/", .shift).menuShortcut)
    }

    func testRejectsExactAndPrefixCollisionsWithinOverlappingContexts() {
        let preferences = Preferences(store: InMemorySettings())
        assertFailure(
            KeyboardShortcutCatalog.set(binding("1", .command), for: "saveNote", preferences: preferences),
            .conflict("Go to Today"))
        assertFailure(
            KeyboardShortcutCatalog.set(binding("g"), for: "quickCapture", preferences: preferences),
            .conflict("Go to Today (G then T)"))
        assertFailure(
            KeyboardShortcutCatalog.set(binding("leftArrow", .command), for: "saveNote", preferences: preferences),
            .conflict("Previous Week"))
        assertFailure(
            KeyboardShortcutCatalog.set(binding("2", .command), for: "panel.refresh", preferences: preferences),
            .conflict("Panel: Agents"))
    }

    func testPanelBindingsMayShareWorkspaceKeysButGlobalMayNot() {
        let preferences = Preferences(store: InMemorySettings())
        XCTAssertNoThrow(
            try KeyboardShortcutCatalog.set(binding("n", .command), for: "panel.refresh", preferences: preferences)
                .get())
        assertFailure(
            KeyboardShortcutCatalog.set(binding("n", .command), for: "globalCapture", preferences: preferences),
            .conflict("Quick Capture"))
    }

    func testRejectsReservedAndInvalidStrokes() {
        let preferences = Preferences(store: InMemorySettings())
        assertFailure(
            KeyboardShortcutCatalog.set(binding("q", .command), for: "chooseVault", preferences: preferences),
            .reservedStroke)
        assertFailure(
            KeyboardShortcutCatalog.set(binding("return"), for: "chooseVault", preferences: preferences),
            .reservedStroke)
        assertFailure(
            KeyboardShortcutCatalog.set(binding("é"), for: "chooseVault", preferences: preferences), .invalidStroke)
        assertFailure(
            KeyboardShortcutCatalog.set(binding("x"), for: "globalCapture", preferences: preferences), .reservedStroke)
        assertFailure(
            KeyboardShortcutCatalog.set(binding("j"), for: "assistant.submit", preferences: preferences),
            .reservedStroke)
        assertFailure(
            KeyboardShortcutCatalog.set(
                ShortcutBinding(ShortcutStroke("g", modifiers: .command), ShortcutStroke("t")),
                for: "assistant.submit", preferences: preferences),
            .reservedStroke)
        assertFailure(
            KeyboardShortcutCatalog.set(binding("leftArrow", .control), for: "globalCapture", preferences: preferences),
            .invalidStroke)
        assertFailure(
            KeyboardShortcutCatalog.set(
                ShortcutBinding(ShortcutStroke("j", modifiers: .command), ShortcutStroke("k")),
                for: "globalCapture", preferences: preferences),
            .invalidStroke)
        XCTAssertEqual(ShortcutStroke("space").carbonKeyCode, 49)
        XCTAssertNil(ShortcutStroke("leftArrow").carbonKeyCode)
    }

    func testPanelBindingsCannotOverrideFixedKeyDelivery() {
        let preferences = Preferences(store: InMemorySettings())
        for key in ["f2", "f4", "f5", "f6", "f7", "f8"] {
            for modifiers in [ShortcutModifiers(), .command, .option] {
                assertFailure(
                    KeyboardShortcutCatalog.set(
                        binding(key, modifiers), for: "panel.refresh", preferences: preferences),
                    .reservedStroke)
            }
        }
        for key in ["f", "e", "p", "v", "s", "w", "h"] {
            assertFailure(
                KeyboardShortcutCatalog.set(binding(key, .option), for: "panel.refresh", preferences: preferences),
                .reservedStroke)
            assertFailure(
                KeyboardShortcutCatalog.set(
                    binding(key, [.option, .shift]), for: "panel.refresh", preferences: preferences),
                .reservedStroke)
        }
        for key in ["leftArrow", "rightArrow", "upArrow", "downArrow", "delete"] {
            assertFailure(
                KeyboardShortcutCatalog.set(binding(key, .command), for: "panel.refresh", preferences: preferences),
                .reservedStroke)
        }
        for key in ["space", "return"] {
            assertFailure(
                KeyboardShortcutCatalog.set(binding(key, .control), for: "panel.refresh", preferences: preferences),
                .reservedStroke)
        }
        XCTAssertEqual(
            KeyboardShortcutCatalog.binding(for: "panel.actions", preferences: preferences),
            binding("return", .command))
    }

    func testAssistantSubmitRequiresDeliverableButtonShortcut() {
        let preferences = Preferences(store: InMemorySettings())
        for key in ["f1", "f2", "f12"] {
            assertFailure(
                KeyboardShortcutCatalog.set(binding(key, .command), for: "assistant.submit", preferences: preferences),
                .reservedStroke)
        }
        XCTAssertNoThrow(
            try KeyboardShortcutCatalog.set(binding("j", .control), for: "assistant.submit", preferences: preferences)
                .get())
    }

    func testSanitizationRejectsUndeliverableOverrides() {
        let sanitized = KeyboardShortcutCatalog.sanitized([
            "panel.refresh": ShortcutOverride(binding("f4", .shift)),
            "assistant.submit": ShortcutOverride(binding("f1", .command)),
            "searchNotes": ShortcutOverride(binding("z")),
        ])
        XCTAssertNil(sanitized["panel.refresh"])
        XCTAssertNil(sanitized["assistant.submit"])
        XCTAssertEqual(sanitized["searchNotes"]?.binding, binding("z"))
    }

    func testSingleResetAndResetAllPersistExplicitUnbound() {
        let store = InMemorySettings()
        let preferences = Preferences(store: store)
        XCTAssertNoThrow(try KeyboardShortcutCatalog.set(nil, for: "go.today", preferences: preferences).get())
        XCTAssertNotNil(store.stored?.shortcutOverrides["go.today"])
        XCTAssertNil(KeyboardShortcutCatalog.binding(for: "go.today", preferences: preferences))
        XCTAssertNoThrow(
            try KeyboardShortcutCatalog.set(binding("z"), for: "searchNotes", preferences: preferences).get())
        XCTAssertNoThrow(try KeyboardShortcutCatalog.reset(for: "go.today", preferences: preferences).get())
        XCTAssertEqual(
            KeyboardShortcutCatalog.binding(for: "go.today", preferences: preferences), binding("1", .command))
        KeyboardShortcutCatalog.resetAll(preferences: preferences)
        XCTAssertTrue(preferences.shortcutOverrides.isEmpty)
        XCTAssertTrue(store.stored?.shortcutOverrides.isEmpty == true)
    }

    func testMalformedOrConflictingHandEditsKeepOtherOverrides() {
        let store = InMemorySettings()
        store.stored = WorkspaceSettings(
            dailyFolder: "safe",
            shortcutOverrides: [
                "saveNote": ShortcutOverride(binding("1", .command)),
                "searchNotes": ShortcutOverride(binding("z")),
                "futureAction": ShortcutOverride(binding("t")),
            ])
        let preferences = Preferences(store: store)
        XCTAssertEqual(preferences.dailyFolder, "safe")
        XCTAssertEqual(
            KeyboardShortcutCatalog.binding(for: "saveNote", preferences: preferences), binding("s", .command))
        XCTAssertEqual(KeyboardShortcutCatalog.binding(for: "searchNotes", preferences: preferences), binding("z"))
        XCTAssertNil(preferences.shortcutOverrides["futureAction"])
    }

    func testRejectedInvalidOverrideRestoresDefaultBeforeConflictResolution() {
        let store = InMemorySettings()
        store.stored = WorkspaceSettings(shortcutOverrides: [
            "go.today": ShortcutOverride(binding("❌")),
            "saveNote": ShortcutOverride(binding("1", .command)),
        ])
        let preferences = Preferences(store: store)
        XCTAssertEqual(
            KeyboardShortcutCatalog.binding(for: "go.today", preferences: preferences), binding("1", .command))
        XCTAssertEqual(
            KeyboardShortcutCatalog.binding(for: "saveNote", preferences: preferences), binding("s", .command))
        XCTAssertTrue(preferences.shortcutOverrides.isEmpty)
    }

    func testRecordingFlagIsTransientAndNeverSaved() {
        let store = InMemorySettings()
        let preferences = Preferences(store: store)
        preferences.isRecordingShortcut = true
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertFalse(Preferences(store: store).isRecordingShortcut)
    }

    func testGoSequenceNavigatesOnlyOnMatchingSecondKeyBeforeTimeout() {
        let preferences = Preferences(store: InMemorySettings())
        let router = MainWindowShortcutRouter()
        XCTAssertEqual(router.accept(ShortcutStroke("g"), preferences: preferences, at: 100), .waiting)
        XCTAssertEqual(
            router.accept(ShortcutStroke("p"), preferences: preferences, at: 101), .action("goChord.projects"))
        XCTAssertNil(router.pendingHint)

        XCTAssertEqual(router.accept(ShortcutStroke("g"), preferences: preferences, at: 200), .waiting)
        XCTAssertEqual(router.accept(ShortcutStroke("p"), preferences: preferences, at: 202), .unhandled)
        XCTAssertEqual(router.accept(ShortcutStroke("p"), preferences: preferences, at: 203), .unhandled)
    }

    func testReboundNavigationSequenceReplacesOriginal() throws {
        let preferences = Preferences(store: InMemorySettings())
        let replacement = ShortcutBinding(ShortcutStroke("z"), ShortcutStroke("p"))
        try KeyboardShortcutCatalog.set(replacement, for: "goChord.projects", preferences: preferences).get()
        let router = MainWindowShortcutRouter()
        XCTAssertEqual(router.accept(ShortcutStroke("z"), preferences: preferences, at: 1), .waiting)
        XCTAssertEqual(
            router.accept(ShortcutStroke("p"), preferences: preferences, at: 2), .action("goChord.projects"))
        XCTAssertEqual(router.accept(ShortcutStroke("g"), preferences: preferences, at: 3), .waiting)
        XCTAssertEqual(router.accept(ShortcutStroke("p"), preferences: preferences, at: 4), .unhandled)
    }

    func testCalendarChordDoesNotConsumeKeysOutsideCalendar() throws {
        let preferences = Preferences(store: InMemorySettings())
        let binding = ShortcutBinding(ShortcutStroke("j"), ShortcutStroke("w"))
        try KeyboardShortcutCatalog.set(binding, for: "calendar.previousWeek", preferences: preferences).get()
        let router = MainWindowShortcutRouter()
        XCTAssertEqual(router.accept(ShortcutStroke("j"), preferences: preferences, activeSection: .today), .unhandled)
        XCTAssertEqual(router.accept(ShortcutStroke("j"), preferences: preferences, activeSection: .calendar), .waiting)
        XCTAssertEqual(
            router.accept(ShortcutStroke("w"), preferences: preferences, activeSection: .calendar),
            .action("calendar.previousWeek"))
    }

    func testQuestionMarkTogglesContextualAIOnEveryPageAndRemainsConfigurable() throws {
        let preferences = Preferences(store: InMemorySettings())
        let router = MainWindowShortcutRouter()
        for section in AppSection.allCases {
            XCTAssertEqual(
                router.accept(ShortcutStroke("/", modifiers: .shift), preferences: preferences, activeSection: section),
                .action("assistant.panel"))
        }
        XCTAssertEqual(router.accept(ShortcutStroke("f1"), preferences: preferences), .action("keyboardHelp"))
        try KeyboardShortcutCatalog.set(binding("a", .option), for: "assistant.panel", preferences: preferences).get()
        XCTAssertEqual(router.accept(ShortcutStroke("/", modifiers: .shift), preferences: preferences), .unhandled)
        XCTAssertEqual(
            router.accept(ShortcutStroke("a", modifiers: .option), preferences: preferences), .action("assistant.panel")
        )
    }

    func testStopShortcutWorksOnAnyPageWhileAssistantInspectorIsVisible() {
        let preferences = Preferences(store: InMemorySettings())
        let router = MainWindowShortcutRouter()
        let stop = ShortcutStroke(".", modifiers: .command)
        XCTAssertEqual(router.accept(stop, preferences: preferences, activeSection: .calendar), .unhandled)
        XCTAssertEqual(
            router.accept(stop, preferences: preferences, activeSection: .calendar, assistantPanelVisible: true),
            .action("assistant.stop"))
    }

}
