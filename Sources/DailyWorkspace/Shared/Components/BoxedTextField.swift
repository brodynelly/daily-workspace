import SwiftUI

/// A single-line text input (Mantine TextInput metrics): the field ground with a strong 3:1 edge, 8 pt radius,
/// body text and a muted placeholder. Focus turns the edge to the focus ring. `secure` hides the text (tokens);
/// `monospaced` is for paths, URLs and ids. Disabled uses the disabled roles, never opacity.
struct BoxedTextField: View {
    let prompt: String
    @Binding var text: String
    var secure = false
    var monospaced = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    init(
        _ prompt: String, text: Binding<String>, secure: Bool = false, monospaced: Bool = false,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.prompt = prompt
        self._text = text
        self.secure = secure
        self.monospaced = monospaced
        self.onSubmit = onSubmit
    }

    var body: some View {
        Group {
            if secure {
                SecureField(prompt, text: $text, prompt: placeholder)
            } else {
                TextField(prompt, text: $text, prompt: placeholder)
            }
        }
        .textFieldStyle(.plain)
        .font(monospaced ? TextRole.mono.font : TextRole.body.font)
        .foregroundStyle(isEnabled ? Theme.ink : Theme.inkDisabled)
        .focused($focused)
        .onSubmit(onSubmit)
        .padding(.horizontal, Space.s3)
        .frame(height: Metrics.controlMd)
        .frame(maxWidth: .infinity)
        .fieldSurface(focused: focused, enabled: isEnabled)
    }

    private var placeholder: Text { Text(prompt).foregroundStyle(Theme.inkMuted) }
}
