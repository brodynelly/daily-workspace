import SwiftUI
import XCTest

@testable import DailyWorkspace

/// The visual foundation: the six screens, the tone taxonomy and the colour roles' contrast, computed from
/// the hex tokens copied from Luuna's `tokens.css`.
final class DesignSystemTests: XCTestCase {
    // MARK: Screens

    func testSectionsAreTheSixScreensInOrder() {
        XCTAssertEqual(
            AppSection.allCases.map(\.title), ["Today", "Projects", "Open Loops", "Notes", "Calendar", "Assistant"])
    }

    func testSectionShortcutsAreCommandOneToSix() {
        for (index, section) in AppSection.allCases.enumerated() {
            XCTAssertEqual(section.shortcut.key.character, Character(String(index + 1)), section.title)
            XCTAssertEqual(section.shortcut.modifiers, .command, section.title)
            XCTAssertEqual(AppCommand.go(section).shortcutLabel, "⌘\(index + 1)")
        }
    }

    func testEverySectionHasOneDescriptiveSentence() {
        for section in AppSection.allCases {
            let sentence = section.description
            XCTAssertTrue(sentence.hasSuffix("."), section.title)
            XCTAssertEqual(sentence.filter { $0 == "." }.count, 1, "\(section.title): one sentence")
            XCTAssertFalse(section.symbol.isEmpty)
        }
    }

    func testPaletteListsTheSixScreensThenSearch() {
        let screens = AppCommand.paletteCommands.prefix(AppSection.allCases.count)
        XCTAssertEqual(Array(screens), AppSection.allCases.map(AppCommand.go))
        XCTAssertTrue(AppCommand.paletteCommands.contains(.searchNotes))
        XCTAssertEqual(AppCommand.searchNotes.shortcutLabel, "⇧⌘F")
        let shortcuts = AppCommand.paletteCommands.map(\.shortcutLabel).filter { !$0.isEmpty }
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count, "no two commands share a shortcut")
    }

    @MainActor
    func testSearchNotesOpensNotesInSearchMode() {
        let model = AppModel(dependencies: .test())
        model.navigation.section = .today
        CommandRunner(model: model, openWindow: EnvironmentValues().openWindow).run(.searchNotes)
        XCTAssertEqual(model.navigation.section, .notes)
        XCTAssertEqual(model.navigation.notesMode, .search)
    }

    // MARK: Tones

    func testEveryToneHasADistinctMark() {
        let marks = Tone.allCases.map(\.mark)
        XCTAssertEqual(Tone.allCases.count, 6)
        XCTAssertEqual(Set(marks).count, Tone.allCases.count)
        XCTAssertEqual(Set(marks), Set(Tone.Mark.allCases))
    }

    func testInterruptionIsNeverDangerAndOnlySuccessIsGreen() {
        XCTAssertNotEqual(Tone.interrupted.markToken, Tone.danger.markToken)
        let green = Tone.allCases.filter { $0.markToken == .success }
        XCTAssertEqual(green, [.success])
    }

    func testVaultStatusLine() {
        let url = URL(fileURLWithPath: "/tmp/vault")
        XCTAssertEqual(VaultSession.State.available(url).statusTone, .success)
        XCTAssertEqual(VaultSession.State.available(url).statusLabel, "Vault connected")
        XCTAssertEqual(VaultSession.State.needsReauthorization.statusTone, .attention)
        XCTAssertEqual(VaultSession.State.unavailable("gone").statusTone, .danger)
        XCTAssertEqual(VaultSession.State.notConfigured.statusTone, .neutral)
    }

    // MARK: Colour

    func testTokensMatchLuuna() {
        XCTAssertEqual(ColorToken.surface.light, RGBA(hex: "#ffffff"))
        XCTAssertEqual(ColorToken.surface.dark, RGBA(hex: "#242424"))
        XCTAssertEqual(ColorToken.accent.light, RGBA(hex: "#1971c2"))
        XCTAssertEqual(ColorToken.accentText.dark, RGBA(hex: "#4dabf7"))
        XCTAssertEqual(ColorToken.scrim.dark.alpha, 0.6)
        XCTAssertEqual(Set(ColorToken.all.map(\.name)).count, ColorToken.all.count, "role names are unique")
    }

    func testTextMeetsAAOnSurfacesInBothSchemes() {
        for dark in [false, true] {
            for ground in [ColorToken.surface, .surfaceRaised] {
                for ink in [ColorToken.ink, .inkBody, .inkMuted] {
                    assertContrast(ink, on: ground, dark: dark, atLeast: 4.5)
                }
            }
        }
    }

    func testAccentMeetsNonTextContrastOnTheSurface() {
        for dark in [false, true] {
            assertContrast(.accent, on: .surface, dark: dark, atLeast: 3)
            assertContrast(.accentText, on: .surface, dark: dark, atLeast: 4.5)
            assertContrast(.inkOnAccent, on: .accent, dark: dark, atLeast: 4.5)
        }
    }

    func testToneTextMeetsAAOnItsGroundAndMarksMeetThreeToOne() {
        for dark in [false, true] {
            for tone in Tone.allCases {
                assertContrast(tone.foregroundToken, on: tone.backgroundToken, dark: dark, atLeast: 4.5)
                assertContrast(tone.markToken, on: .surface, dark: dark, atLeast: 3)
            }
        }
    }

    func testContrastFormula() {
        XCTAssertEqual(RGBA(hex: "#000000").contrast(with: RGBA(hex: "#ffffff")), 21, accuracy: 0.001)
        XCTAssertEqual(RGBA(hex: "#777777").contrast(with: RGBA(hex: "#777777")), 1, accuracy: 0.001)
    }

    func testDynamicColourFollowsTheAppearance() throws {
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        XCTAssertTrue(ColorToken.isDark(dark))
        XCTAssertFalse(ColorToken.isDark(light))
        var resolved: [CGFloat] = []
        for appearance in [light, dark] {
            appearance.performAsCurrentDrawingAppearance {
                let color = ColorToken.surface.nsColor.usingColorSpace(.sRGB)
                resolved.append(color?.redComponent ?? -1)
            }
        }
        XCTAssertEqual(resolved[0], 1, accuracy: 0.001)
        XCTAssertEqual(resolved[1], 0x24 / 255, accuracy: 0.001)
    }

    // MARK: Type and identities

    func testTypeRolesMatchLuuna() {
        XCTAssertEqual(TextRole.pageTitle.size, 26)
        XCTAssertEqual(TextRole.pageTitle.lineHeight, 1.35)
        XCTAssertEqual(TextRole.pageTitle.family, .display)
        XCTAssertEqual(TextRole.sectionTitle.size, 18)
        XCTAssertEqual(TextRole.metric.size, 20)
        XCTAssertEqual(TextRole.body.size, 16)
        XCTAssertEqual(TextRole.body.lineHeight, 1.55)
        XCTAssertEqual(TextRole.label.size, 14)
        XCTAssertEqual(TextRole.label.weight, .semibold)
        XCTAssertEqual(TextRole.caption.size, 12)
        XCTAssertEqual(TextRole.mono.family, .mono)
        for role in TextRole.allCases { XCTAssertGreaterThanOrEqual(role.leading, 0) }
    }

    func testShortIdShowsEightHexDigits() {
        XCTAssertEqual(ShortId.shortForm("ticket-0f3a9c21-1b2c-4d5e-8f90-123456789abc"), "0f3a9c21")
        XCTAssertEqual(ShortId.shortForm("0F3A9C21-1B2C-4D5E-8F90-123456789ABC"), "0f3a9c21")
        XCTAssertEqual(ShortId.shortForm("9ea1d23f5c0e8b7a6d4c3b2a1f0e9d8c7b6a5f4e"), "9ea1d23f")
        XCTAssertEqual(ShortId.shortForm("sha256:" + String(repeating: "ab", count: 32)), "sha256:abababababab")
        XCTAssertEqual(ShortId.shortForm("9ea1d23"), "9ea1d23")
        XCTAssertEqual(ShortId.shortForm("project:alpha"), "project:alpha")
    }

    private func assertContrast(
        _ text: ColorToken, on ground: ColorToken, dark: Bool, atLeast minimum: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let ratio = text.value(dark: dark).contrast(with: ground.value(dark: dark))
        XCTAssertGreaterThanOrEqual(
            ratio, minimum,
            "\(text.name) on \(ground.name) (\(dark ? "dark" : "light")): \(String(format: "%.2f", ratio)):1",
            file: file, line: line)
    }
}
