import SwiftUI

private struct QuickPanelFontKey: EnvironmentKey {
    static let defaultValue = "VGA"
}

extension EnvironmentValues {
    /// The panel's configured font name, set once at the panel root so every view matches.
    var quickPanelFont: String {
        get { self[QuickPanelFontKey.self] }
        set { self[QuickPanelFontKey.self] = newValue }
    }
}

/// The panel font at a size, falling back to the system monospaced font like the rest of the panel.
private struct QuickPanelFontModifier: ViewModifier {
    @Environment(\.quickPanelFont) private var name
    let size: CGFloat
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        let font = PascalType.font(size, preferred: name)
        content.font(weight.map { font.weight($0) } ?? font)
    }
}

extension View {
    func panelFont(_ size: CGFloat, weight: Font.Weight? = nil) -> some View {
        modifier(QuickPanelFontModifier(size: size, weight: weight))
    }
}
