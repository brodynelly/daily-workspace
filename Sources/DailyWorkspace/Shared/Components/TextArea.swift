import SwiftUI

/// A multi-line text input on the field ground: body text, an optional muted placeholder, and the focus ring
/// while focused. `label` is the accessible name (pair it with `LabeledField` for a visible label). Disabled
/// uses the disabled ground and ink, never opacity.
struct TextArea: View {
    let label: String
    @Binding var text: String
    var prompt: String?
    var height: CGFloat = 64
    var monospaced = false

    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    init(
        _ label: String, text: Binding<String>, prompt: String? = nil, height: CGFloat = 64,
        monospaced: Bool = false
    ) {
        self.label = label
        self._text = text
        self.prompt = prompt
        self.height = height
        self.monospaced = monospaced
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(monospaced ? TextRole.mono.font : TextRole.body.font)
                .foregroundStyle(isEnabled ? Theme.ink : Theme.inkDisabled)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(Space.s2)
                .accessibilityLabel(label)
            if text.isEmpty, let prompt {
                // TextEditor insets its text by about 5 pt; the placeholder sits on the same first line.
                Text(prompt)
                    .textRole(.body, lineBox: false)
                    .foregroundStyle(isEnabled ? Theme.inkMuted : Theme.inkDisabled)
                    .padding(.horizontal, Space.s3 - 1)
                    .padding(.vertical, Space.s2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: height)
        .fieldSurface(focused: focused, enabled: isEnabled)
    }
}

/// Read-only text shown exactly as stored (a file preview, a before/after, a diff line block): monospaced
/// caption type on the muted ground, selectable, scrolling inside a fixed height.
struct CodePreview: View {
    let text: String
    var height: CGFloat = 200

    var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(TextRole.monoCaption.font)
                .foregroundStyle(Theme.inkBody)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Space.s3)
        }
        .frame(height: height)
        .mutedSurface()
    }
}
