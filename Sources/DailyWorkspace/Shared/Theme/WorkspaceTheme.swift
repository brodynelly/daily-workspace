import AppKit
import SwiftUI

/// Legacy names kept so earlier call sites compile, each pointing at a Luuna role (like Luuna's
/// `tokens-legacy.css`). New code uses `Theme`, `Radius`, `Space`, `Metrics` and `TextRole` directly;
/// migrate a caller to the role and delete the alias when nothing reads it.
enum WorkspaceTheme {
    /// `--surface`.
    static let background = Theme.surface
    /// `--fill`: a quiet grouped ground.
    static let recessed = Theme.fill
    /// `--separator`: hairlines.
    static let border = Theme.separator
    /// `--accent`.
    static var accent: Color { Theme.accent }
    /// `--accent-text` for AppKit drawing (links and the caret): readable on the surface in both schemes.
    static var nativeAccent: NSColor { accentTextNSColor }

    private static let accentTextNSColor = ColorToken.accentText.nsColor
}

/// The window's ground: the surface role, edge to edge.
struct WorkspaceCanvas: View {
    var body: some View { Theme.surface.ignoresSafeArea() }
}

/// A quiet grouped surface: the fill role with a separator hairline.
struct SoftControlSurface: ViewModifier {
    var radius: CGFloat = Radius.md
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.fill)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: Metrics.borderWidth)
                }
        }
    }
}

/// A raised card (Mantine Card): surface-raised, a separator hairline, the md radius, and the xs shadow in
/// light only (dark cards get depth from surface steps, never a shadow).
struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = Radius.md
    var fill: Color = Theme.surfaceRaised

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: Metrics.borderWidth)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 1.5, y: 1)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.1), radius: 1, y: 1)
        }
    }
}

/// A view entering: an opacity fade at the standard duration, from transparent. Nothing else moves, and
/// it is instant under Reduce Motion. The previous view is already gone, so nothing shows behind it.
struct ViewEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    func body(content: Content) -> some View {
        content
            .opacity(entered || reduceMotion ? 1 : 0)
            .onAppear {
                guard !entered else { return }
                withAnimation(Motion.entrance(reduceMotion: reduceMotion)) { entered = true }
            }
    }
}

extension View {
    func softControlSurface(radius: CGFloat = Radius.md) -> some View { modifier(SoftControlSurface(radius: radius)) }
    func cardSurface(radius: CGFloat = Radius.md, fill: Color = Theme.surfaceRaised) -> some View {
        modifier(CardSurface(radius: radius, fill: fill))
    }
    func viewEntrance() -> some View { modifier(ViewEntrance()) }
}
