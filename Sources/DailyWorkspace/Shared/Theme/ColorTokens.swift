import AppKit
import SwiftUI

/// An sRGB colour with alpha, parsed from a CSS hex literal ("#1971c2").
struct RGBA: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(hex: String, alpha: Double = 1) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            preconditionFailure("A colour token must be #rrggbb, got \(hex)")
        }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
        self.alpha = alpha
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    /// WCAG 2.1 relative luminance (alpha ignored).
    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG 2.1 contrast ratio between two opaque colours.
    func contrast(with other: RGBA) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// One colour role from Luuna's `tokens.css` (the Mantine default theme): its exact light and dark values.
/// Light is the default; dark applies when the effective appearance is dark.
struct ColorToken: Hashable, Sendable {
    let name: String
    let light: RGBA
    let dark: RGBA

    init(_ name: String, light: String, dark: String, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.name = name
        self.light = RGBA(hex: light, alpha: lightAlpha)
        self.dark = RGBA(hex: dark, alpha: darkAlpha)
    }

    func value(dark isDark: Bool) -> RGBA { isDark ? dark : light }

    /// A dynamic colour that follows the drawing appearance (and so the macOS scheme).
    var nsColor: NSColor {
        let light = light.nsColor
        let dark = dark.nsColor
        return NSColor(name: NSColor.Name("luuna." + name)) { appearance in
            ColorToken.isDark(appearance) ? dark : light
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        let match = appearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ])
        return match == .darkAqua || match == .accessibilityHighContrastDarkAqua
    }
}

/// The colour roles, values copied verbatim from `packages/ui/src/styles/tokens.css`.
extension ColorToken {
    // Surfaces.
    static let surface = ColorToken("surface", light: "#ffffff", dark: "#242424")
    static let surfaceRaised = ColorToken("surface-raised", light: "#ffffff", dark: "#242424")
    static let surfaceMuted = ColorToken("surface-muted", light: "#f8f9fa", dark: "#1f1f1f")
    static let fill = ColorToken("fill", light: "#f1f3f5", dark: "#2e2e2e")
    static let fillStrong = ColorToken("fill-strong", light: "#e9ecef", dark: "#3b3b3b")
    static let controlSelected = ColorToken("control-selected", light: "#ffffff", dark: "#424242")
    static let surfaceOverlay = ColorToken("surface-overlay", light: "#ffffff", dark: "#2e2e2e")
    static let field = ColorToken("field", light: "#ffffff", dark: "#2e2e2e")
    static let scrim = ColorToken("scrim", light: "#000000", dark: "#000000", lightAlpha: 0.4, darkAlpha: 0.6)
    static let banner = ColorToken("banner", light: "#212529", dark: "#2e2e2e")
    /// Mantine's disabled ground (controls.css): fill-strong in light, fill in dark.
    static let surfaceDisabled = ColorToken("surface-disabled", light: "#e9ecef", dark: "#2e2e2e")

    // Lines.
    static let separator = ColorToken("separator", light: "#dee2e6", dark: "#3b3b3b")
    static let border = ColorToken("border", light: "#ced4da", dark: "#424242")
    static let borderStrong = ColorToken("border-strong", light: "#868e96", dark: "#828282")

    // Text.
    static let ink = ColorToken("ink", light: "#000000", dark: "#ffffff")
    static let inkBody = ColorToken("ink-body", light: "#000000", dark: "#c9c9c9")
    static let inkMuted = ColorToken("ink-muted", light: "#495057", dark: "#b8b8b8")
    static let inkSubdued = ColorToken("ink-subdued", light: "#495057", dark: "#b8b8b8")
    static let inkDisabled = ColorToken("ink-disabled", light: "#adb5bd", dark: "#696969")
    static let inkOnBanner = ColorToken("ink-on-banner", light: "#ffffff", dark: "#c9c9c9")

    // Accent: the developer acts (primary actions, the next step, focus, selection).
    static let accent = ColorToken("accent", light: "#1971c2", dark: "#1971c2")
    static let accentHover = ColorToken("accent-hover", light: "#1864ab", dark: "#1864ab")
    static let inkOnAccent = ColorToken("ink-on-accent", light: "#ffffff", dark: "#ffffff")
    static let accentText = ColorToken("accent-text", light: "#1971c2", dark: "#4dabf7")
    static let accentSoft = ColorToken("accent-soft", light: "#e7f5ff", dark: "#22303c")
    static let focusRing = ColorToken("focus-ring", light: "#228be6", dark: "#1c7ed6")

    // Toast and charts.
    static let toast = ColorToken("toast", light: "#212529", dark: "#3b3b3b")
    static let inkOnToast = ColorToken("ink-on-toast", light: "#ffffff", dark: "#ffffff")
    static let toastAction = ColorToken("toast-action", light: "#a5d8ff", dark: "#74c0fc")
    static let chart1 = ColorToken("chart-1", light: "#228be6", dark: "#339af0")
    static let chart2 = ColorToken("chart-2", light: "#7950f2", dark: "#845ef7")
    static let chart3 = ColorToken("chart-3", light: "#12b886", dark: "#20c997")
    static let chart4 = ColorToken("chart-4", light: "#fd7e14", dark: "#ff922b")
    static let chart5 = ColorToken("chart-5", light: "#e64980", dark: "#f06595")
    /// Reserved for AI output.
    static let ai = ColorToken("ai", light: "#7048e8", dark: "#9775fa")
    static let chartMuted = ColorToken("chart-muted", light: "#ced4da", dark: "#424242")
    static let chartGrid = ColorToken("chart-grid", light: "#e9ecef", dark: "#3b3b3b")

    // Status: each with a soft ground.
    static let success = ColorToken("success", light: "#087f5b", dark: "#12b886")
    static let successSoft = ColorToken("success-soft", light: "#e6fcf5", dark: "#20352e")
    static let danger = ColorToken("danger", light: "#c92a2a", dark: "#ff6b6b")
    static let inkOnDanger = ColorToken("ink-on-danger", light: "#ffffff", dark: "#000000")
    static let dangerSoft = ColorToken("danger-soft", light: "#fff5f5", dark: "#402626")
    static let warning = ColorToken("warning", light: "#c8420e", dark: "#fd7e14")
    static let warningSoft = ColorToken("warning-soft", light: "#fff4e6", dark: "#412c20")
    static let info = ColorToken("info", light: "#1971c2", dark: "#4dabf7")
    static let infoSoft = ColorToken("info-soft", light: "#e7f5ff", dark: "#22303c")

    /// Every role, so tests can check both schemes and every contrast pair.
    static let all: [ColorToken] = [
        .surface, .surfaceRaised, .surfaceMuted, .fill, .fillStrong, .controlSelected, .surfaceOverlay, .field,
        .scrim, .banner, .surfaceDisabled, .separator, .border, .borderStrong, .ink, .inkBody, .inkMuted,
        .inkSubdued, .inkDisabled, .inkOnBanner, .accent, .accentHover, .inkOnAccent, .accentText, .accentSoft,
        .focusRing, .toast, .inkOnToast, .toastAction, .chart1, .chart2, .chart3, .chart4, .chart5, .ai,
        .chartMuted, .chartGrid, .success, .successSoft, .danger, .inkOnDanger, .dangerSoft, .warning,
        .warningSoft, .info, .infoSoft,
    ]
}
