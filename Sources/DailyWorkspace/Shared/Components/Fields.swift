import SwiftUI

/// A search field (Mantine TextInput metrics): the field ground with a strong 3:1 edge, 8 pt radius, body
/// text, a muted placeholder. Focus turns the edge to the focus ring.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    init(_ prompt: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) {
        self.prompt = prompt
        self._text = text
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .iconRole(.inline)
                .foregroundStyle(Theme.inkMuted)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Theme.inkMuted))
                .textFieldStyle(.plain)
                .font(TextRole.body.font)
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.s3)
        .frame(height: Metrics.controlMd)
        .fieldSurface(focused: focused)
        .onAppear { focused = true }
    }
}

/// An on/off control that applies at once in a header (Preview, Backlinks): quiet while off; on, it is
/// raised with a strong edge like a selected segment. Never the accent: it is a view choice.
struct QuietToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietToggleBody(configuration: configuration)
    }
}

private struct QuietToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        let isOn = configuration.isOn
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(TextRole.label.font)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isEnabled ? (isOn ? Theme.ink : Theme.inkBody) : Theme.inkDisabled)
                .padding(.horizontal, Space.s3)
                .frame(minHeight: Metrics.controlMd)
                .surface(
                    isOn ? Theme.surfaceRaised : hovered && isEnabled ? Theme.fill : .clear,
                    edge: isOn ? Theme.borderStrong : nil)
                .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension ToggleStyle where Self == QuietToggleStyle {
    static var quiet: QuietToggleStyle { QuietToggleStyle() }
}
