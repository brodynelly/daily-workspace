import SwiftUI

/// A form field (Luuna `label` wrapping a field): the label text above the control, an optional muted hint
/// under it. The label is the control's accessible name.
struct LabeledField<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: Content

    init(_ label: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1Half) {
            Text(label)
                .textRole(.label, lineBox: false)
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            content.accessibilityLabel(label)
            if let hint {
                Text(hint)
                    .textRole(.caption, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The field chrome (Mantine TextInput metrics) for a `.plain` text field: the field ground, a strong 3:1
/// edge that turns to the focus ring while focused, 8 pt radius and body text. Disabled uses the disabled
/// ground and ink, never opacity.
struct FieldChrome: ViewModifier {
    var focused: Bool
    var monospaced = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(monospaced ? TextRole.mono.font : TextRole.body.font)
            .foregroundStyle(isEnabled ? Theme.ink : Theme.inkDisabled)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s1Half)
            .frame(minHeight: Metrics.controlMd)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isEnabled ? Theme.field : Theme.surfaceDisabled)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(
                        focused && isEnabled ? Theme.focusRing : Theme.borderStrong, lineWidth: Metrics.borderWidth)
            }
    }
}

extension View {
    /// Draws Luuna's field chrome around a text field; pass the field's focus state.
    func fieldChrome(focused: Bool, monospaced: Bool = false) -> some View {
        modifier(FieldChrome(focused: focused, monospaced: monospaced))
    }
}

/// The end of a form (Luuna `.form-footer`): a muted hint on the left and the actions on the right, the
/// primary last. The actions keep the right edge even when the hint wraps.
struct FormFooter<Actions: View>: View {
    var hint: String?
    @ViewBuilder var actions: Actions

    init(hint: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.hint = hint
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            Text(hint ?? "")
                .textRole(.bodySmall, lineBox: false)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(hint == nil)
            HStack(spacing: Space.s2) { actions }.fixedSize()
        }
    }
}
