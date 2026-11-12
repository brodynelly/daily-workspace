import SwiftUI

/// The colour roles as SwiftUI colours: `Theme.ink`, `Theme.surface`, `Theme.accent`.
/// Each follows the macOS appearance (light by default, dark when the window is dark).
/// Values and rules: Luuna's `docs/DESIGN-SYSTEM.md` and `tokens.css`; hex lives in `ColorToken`.
enum Theme {
    // Surfaces.
    static let surface = ColorToken.surface.color
    static let surfaceRaised = ColorToken.surfaceRaised.color
    static let surfaceMuted = ColorToken.surfaceMuted.color
    static let fill = ColorToken.fill.color
    static let fillStrong = ColorToken.fillStrong.color
    static let controlSelected = ColorToken.controlSelected.color
    static let surfaceOverlay = ColorToken.surfaceOverlay.color
    static let field = ColorToken.field.color
    static let scrim = ColorToken.scrim.color
    static let banner = ColorToken.banner.color
    static let surfaceDisabled = ColorToken.surfaceDisabled.color

    // Lines: separator for hairlines, border for decorative edges, borderStrong for 3:1 control edges.
    static let separator = ColorToken.separator.color
    static let border = ColorToken.border.color
    static let borderStrong = ColorToken.borderStrong.color

    // Text.
    static let ink = ColorToken.ink.color
    static let inkBody = ColorToken.inkBody.color
    static let inkMuted = ColorToken.inkMuted.color
    static let inkSubdued = ColorToken.inkSubdued.color
    static let inkDisabled = ColorToken.inkDisabled.color
    static let inkOnBanner = ColorToken.inkOnBanner.color

    // Accent: primary actions, the next step, focus and selection. Never runtime activity (that is `info`).
    static let accent = ColorToken.accent.color
    static let accentHover = ColorToken.accentHover.color
    static let inkOnAccent = ColorToken.inkOnAccent.color
    static let accentText = ColorToken.accentText.color
    static let accentSoft = ColorToken.accentSoft.color
    static let focusRing = ColorToken.focusRing.color

    // Toast, charts and AI output.
    static let toast = ColorToken.toast.color
    static let inkOnToast = ColorToken.inkOnToast.color
    static let toastAction = ColorToken.toastAction.color
    static let chart1 = ColorToken.chart1.color
    static let chart2 = ColorToken.chart2.color
    static let chart3 = ColorToken.chart3.color
    static let chart4 = ColorToken.chart4.color
    static let chart5 = ColorToken.chart5.color
    static let ai = ColorToken.ai.color
    static let chartMuted = ColorToken.chartMuted.color
    static let chartGrid = ColorToken.chartGrid.color

    // Status. Read these through `Tone`, not directly, so every state keeps its shape mark.
    static let success = ColorToken.success.color
    static let successSoft = ColorToken.successSoft.color
    static let danger = ColorToken.danger.color
    static let inkOnDanger = ColorToken.inkOnDanger.color
    static let dangerSoft = ColorToken.dangerSoft.color
    static let warning = ColorToken.warning.color
    static let warningSoft = ColorToken.warningSoft.color
    static let info = ColorToken.info.color
    static let infoSoft = ColorToken.infoSoft.color
}

/// Mantine radii (tokens-depth.css). Components use `sm` and `md`; `md` is the default.
enum Radius {
    static let xs: CGFloat = 2
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 16
    static let xl: CGFloat = 32
    static let full: CGFloat = 9999
}

/// Spacing (tokens-scale.css): the 4 pt layout rhythm (`s1` = 4 … `s12` = 48, plus half steps),
/// and Mantine's `xs`…`xl` (10, 12, 16, 20, 32).
enum Space {
    static let sHalf: CGFloat = 2
    static let s1: CGFloat = 4
    static let s1Half: CGFloat = 6
    static let s2: CGFloat = 8
    static let s2Half: CGFloat = 10
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s12: CGFloat = 48

    static let xs: CGFloat = 10
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 32
}

/// Control, layout and component sizes (tokens-scale.css, tokens-motion.css, tokens-depth.css).
enum Metrics {
    /// Control heights: compact (text buttons), default, large (page-header actions).
    static let controlSm: CGFloat = 28
    static let controlMd: CGFloat = 32
    static let controlLg: CGFloat = 40
    static let controlPadX: CGFloat = 18
    static let controlPadXLg: CGFloat = 22

    static let sidebarWidth: CGFloat = 240
    static let topBarHeight: CGFloat = 56
    static let contentMaxWidth: CGFloat = 1200
    /// The page's padding inside the content column: 20 on top, 32 at the sides and bottom.
    static let pagePadding = EdgeInsets(top: Space.s5, leading: Space.s8, bottom: Space.s8, trailing: Space.s8)
    /// Readable width for a description sentence (about 72 characters at 16 pt).
    static let measure: CGFloat = 640
    static let paletteTriggerMaxWidth: CGFloat = 440

    static let borderWidth: CGFloat = 1
    static let ruleWidth: CGFloat = 3
    static let markSize: CGFloat = 8
    static let markStroke: CGFloat = 2
    static let iconSize: CGFloat = 16
    static let rowHeight: CGFloat = 40
    static let badgeHeight: CGFloat = 20
    static let kbdSize: CGFloat = 20
    static let factsTerm: CGFloat = 150
    static let emptyDescriptionMax: CGFloat = 360
}

/// Durations and easings (tokens-motion.css). Only functional motion: state colour changes and the
/// view-change fade. Every animation is instant under Reduce Motion.
enum Motion {
    static let micro: Double = 0.14
    static let standard: Double = 0.22

    /// `--ease-standard`, for state changes.
    static func standardEase(_ duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
    /// `--ease-out`, for entrances.
    static func easeOut(_ duration: Double) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: duration) }

    /// A state change (`--duration-micro`), or nil under Reduce Motion.
    static func stateChange(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : standardEase(micro) }
    /// A view entering (`--duration-standard`, ease-out), or nil under Reduce Motion.
    static func entrance(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : easeOut(standard) }
}
