import SwiftUI
import AppKit

/// Semantic tokens backed by dynamic system colors, so light, dark, Increase Contrast,
/// and the person's chosen accent color all work without app-specific overrides.
enum WorkspaceTheme {
    static let background = Color(nsColor: .textBackgroundColor)
    static let recessed = Color(nsColor: .quaternarySystemFill)
    static let border = Color(nsColor: .separatorColor)
    static var accent: Color { .accentColor }
    static var nativeAccent: NSColor { .controlAccentColor }
}

struct WorkspaceCanvas: View {
    var body: some View { WorkspaceTheme.background.ignoresSafeArea() }
}

/// A quiet grouped surface: system fill with a hairline separator edge.
struct SoftControlSurface: ViewModifier {
    var radius: CGFloat = 8
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(WorkspaceTheme.recessed)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(WorkspaceTheme.border, lineWidth: 0.5)
                }
        }
    }
}

extension View {
    func softControlSurface(radius: CGFloat = 8) -> some View { modifier(SoftControlSurface(radius: radius)) }
}
