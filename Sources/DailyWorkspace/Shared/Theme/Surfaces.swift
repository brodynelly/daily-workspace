import SwiftUI

/// The one rounded surface every container draws: a fill, an optional 1 pt edge on top of the content, the
/// continuous md radius. Cards, trays, callouts, fields and selected rows are all this primitive with a role.
struct SurfaceModifier: ViewModifier {
    var fill: Color
    var edge: Color?
    var radius: CGFloat = Radius.md

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay {
                if let edge {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(edge, lineWidth: Metrics.borderWidth)
                }
            }
    }
}

/// The field ground (Mantine TextInput): the field fill with a strong 3:1 edge that turns to the focus ring
/// while focused. Disabled uses the disabled ground and a quiet edge, never opacity.
struct FieldSurfaceModifier: ViewModifier {
    var focused: Bool
    var enabled: Bool

    func body(content: Content) -> some View {
        content.surface(
            enabled ? Theme.field : Theme.surfaceDisabled,
            edge: !enabled ? Theme.border : focused ? Theme.focusRing : Theme.borderStrong)
    }
}

/// A quiet grouped surface: the fill role with a separator hairline.
struct SoftControlSurface: ViewModifier {
    var radius: CGFloat = Radius.md
    func body(content: Content) -> some View {
        content.surface(Theme.fill, edge: Theme.separator, radius: radius)
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
    /// A rounded surface in a colour role, with an optional 1 pt edge.
    func surface(_ fill: Color, edge: Color? = nil, radius: CGFloat = Radius.md) -> some View {
        modifier(SurfaceModifier(fill: fill, edge: edge, radius: radius))
    }

    /// The muted inset ground for previews, quotes and transcripts (no edge).
    func mutedSurface(radius: CGFloat = Radius.md) -> some View { surface(Theme.surfaceMuted, radius: radius) }

    /// The field ground for a custom input; pass its focus state and whether it accepts input.
    func fieldSurface(focused: Bool, enabled: Bool = true) -> some View {
        modifier(FieldSurfaceModifier(focused: focused, enabled: enabled))
    }

    func softControlSurface(radius: CGFloat = Radius.md) -> some View { modifier(SoftControlSurface(radius: radius)) }

    func cardSurface(radius: CGFloat = Radius.md, fill: Color = Theme.surfaceRaised) -> some View {
        modifier(CardSurface(radius: radius, fill: fill))
    }

    func viewEntrance() -> some View { modifier(ViewEntrance()) }
}

/// The window's ground: the surface role, edge to edge.
struct WorkspaceCanvas: View {
    var body: some View { Theme.surface.ignoresSafeArea() }
}
