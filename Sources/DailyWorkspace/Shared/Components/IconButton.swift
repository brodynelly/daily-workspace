import SwiftUI

/// A 28 pt icon-only button for rows and toolbars: no chrome until hovered, then the fill. Nothing lifts or
/// scales. `label` is both the tooltip and the accessible name, so an icon never stands alone.
struct RowIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .iconRole(.control)
                .foregroundStyle(isEnabled ? Theme.inkBody : Theme.inkDisabled)
                .frame(width: Metrics.controlSm, height: Metrics.controlSm)
                .surface(hovered && isEnabled ? Theme.fill : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
