import SwiftUI

/// Luuna's push buttons (Mantine metrics): 14 pt semibold, 8 pt radius, 18 pt side padding.
/// - `secondary` (the default): the raised surface with a border.
/// - `primary`: the accent fill. At most one per action group: the accent means Brody acts.
/// - `quiet`: no fill or border until hovered (toolbar and top-bar actions).
/// - `danger`: the solid danger role.
/// - `text`: an accent text link, compact.
/// Hover changes only the background, press darkens it; nothing lifts or scales. Disabled uses the
/// disabled colour roles, never opacity.
struct WorkspaceButtonStyle: ButtonStyle {
    enum Variant: Sendable { case secondary, primary, quiet, danger, text }
    /// Heights 28 (compact), 32 (default) and 40 (page-header actions).
    enum Size: Sendable { case small, medium, large }

    var variant: Variant = .secondary
    var size: Size = .medium

    func makeBody(configuration: Configuration) -> some View {
        WorkspaceButtonBody(configuration: configuration, variant: variant, size: size)
    }
}

private struct WorkspaceButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: WorkspaceButtonStyle.Variant
    let size: WorkspaceButtonStyle.Size

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    private var pressed: Bool { configuration.isPressed }

    var body: some View {
        configuration.label
            .font(TextRole.label.font)
            .lineLimit(1)
            .fixedSize()
            .labelStyle(ButtonLabelStyle())
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(border, lineWidth: Metrics.borderWidth)
            }
            .underline(variant == .text && hovered && isEnabled)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .onHover { hovered = $0 }
    }

    private var height: CGFloat {
        if variant == .text { return Metrics.controlSm }
        switch size {
        case .small: return Metrics.controlSm
        case .medium: return Metrics.controlMd
        case .large: return Metrics.controlLg
        }
    }

    private var horizontalPadding: CGFloat {
        if variant == .text { return Space.s2 }
        switch size {
        case .small: return Space.s3
        case .medium: return Metrics.controlPadX
        case .large: return Metrics.controlPadXLg
        }
    }

    private var active: Bool { isEnabled && (hovered || pressed) }

    private var foreground: Color {
        guard isEnabled else { return Theme.inkDisabled }
        switch variant {
        case .secondary, .quiet: return Theme.inkBody
        case .primary: return Theme.inkOnAccent
        case .danger: return Theme.inkOnDanger
        case .text: return Theme.accentText
        }
    }

    private var background: Color {
        switch variant {
        case .secondary:
            guard isEnabled else { return Theme.surfaceDisabled }
            return pressed ? Theme.fillStrong : hovered ? Theme.fill : Theme.surfaceRaised
        case .primary:
            guard isEnabled else { return Theme.surfaceDisabled }
            return active ? Theme.accentHover : Theme.accent
        case .danger:
            guard isEnabled else { return Theme.surfaceDisabled }
            return Theme.danger
        case .quiet:
            guard isEnabled else { return .clear }
            return pressed ? Theme.fillStrong : hovered ? Theme.fill : .clear
        case .text:
            return .clear
        }
    }

    private var border: Color {
        guard isEnabled else { return .clear }
        switch variant {
        case .secondary: return Theme.border
        case .primary: return active ? Theme.accentHover : Theme.accent
        // The palette has no shade darker than danger: hover and press add an inner hairline instead.
        case .danger: return active ? Theme.inkOnDanger : Theme.danger
        case .quiet, .text: return .clear
        }
    }
}

/// Icon and title 10 pt apart, the icon at 16 pt.
private struct ButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s2Half) {
            configuration.icon.font(.system(size: 13, weight: .regular)).imageScale(.medium)
            configuration.title
        }
    }
}

extension ButtonStyle where Self == WorkspaceButtonStyle {
    /// The default button: raised surface and a border.
    static var secondary: WorkspaceButtonStyle { WorkspaceButtonStyle(variant: .secondary) }
    /// The one primary action of a group: the accent fill.
    static var primary: WorkspaceButtonStyle { WorkspaceButtonStyle(variant: .primary) }
    /// No chrome until hovered.
    static var quiet: WorkspaceButtonStyle { WorkspaceButtonStyle(variant: .quiet) }
    /// A destructive action.
    static var danger: WorkspaceButtonStyle { WorkspaceButtonStyle(variant: .danger) }
    /// An accent text link.
    static var text: WorkspaceButtonStyle { WorkspaceButtonStyle(variant: .text) }

    static func workspace(_ variant: WorkspaceButtonStyle.Variant, size: WorkspaceButtonStyle.Size) -> Self {
        WorkspaceButtonStyle(variant: variant, size: size)
    }
}

/// A small set of mutually exclusive choices (Mantine SegmentedControl): the selected segment is raised
/// with a strong edge and ink text, the rest muted on the fill. Not an accent: choosing a mode is not a
/// call to action.
struct SegmentedControl<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    init(_ label: String, selection: Binding<Value>, options: [(value: Value, title: String)]) {
        self.label = label
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index])
            }
        }
        .padding(Space.s1 - 1)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.fill))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Theme.borderStrong, lineWidth: Metrics.borderWidth)
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ option: (value: Value, title: String)) -> some View {
        let selected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(TextRole.label.font)
                .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
                .padding(.horizontal, Space.s2Half)
                .padding(.vertical, Space.s1)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Theme.surfaceRaised)
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(Theme.borderStrong, lineWidth: Metrics.borderWidth)
                            }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
