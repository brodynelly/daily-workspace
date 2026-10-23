import SwiftUI

/// Shared palette derived from the supplied charcoal, blue-black, and coral references.
enum WorkspaceTheme {
    static let background = Color(red: 0.065, green: 0.067, blue: 0.073)
    static let coral = Color(red: 1, green: 0.36, blue: 0.38)
    static let ink = Color(red: 0.94, green: 0.94, blue: 0.95)
}

struct WorkspaceCanvas: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        WorkspaceTheme.background
            .overlay(alignment: .topLeading) {
                if !reduceTransparency {
                    RadialGradient(colors: [Color(red: 0.04, green: 0.12, blue: 0.25).opacity(0.48), .clear], center: .topLeading, startRadius: 0, endRadius: 650)
                }
            }
            .ignoresSafeArea()
    }
}

struct SoftControlSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(white: 0.17)) : AnyShapeStyle(.regularMaterial))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.13), lineWidth: 1)
                    }
            }
    }
}

extension View {
    func softControlSurface() -> some View { modifier(SoftControlSurface()) }
}
