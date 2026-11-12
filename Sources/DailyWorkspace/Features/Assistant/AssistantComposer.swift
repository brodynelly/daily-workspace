import SwiftUI

/// The question field: several lines, ⌘↩ or Ask sends. Disabled while an answer or a draft is running.
struct AssistantComposer: View {
    @EnvironmentObject private var assistant: AssistantSession
    @Binding var text: String

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(TextRole.body.font)
                    .foregroundStyle(assistant.isStreaming ? Theme.inkDisabled : Theme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .disabled(assistant.isStreaming)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, Space.s2)
                    .accessibilityLabel("Question")
                if text.isEmpty {
                    Text("Ask about a project, what is due, or a note…")
                        .textRole(.body, lineBox: false)
                        .foregroundStyle(assistant.isStreaming ? Theme.inkDisabled : Theme.inkMuted)
                        .padding(.horizontal, Space.s3 - 1)
                        .padding(.vertical, Space.s2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(assistant.isStreaming ? Theme.surfaceDisabled : Theme.field)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(focused ? Theme.focusRing : Theme.borderStrong, lineWidth: Metrics.borderWidth)
            }
            HStack(spacing: Space.s3) {
                Text("Questions and what the Assistant reads to answer them are sent to Anthropic.")
                    .textRole(.caption, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s3)
                Kbd("⌘↩")
                Button("Ask", action: send)
                    .buttonStyle(.primary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSend)
            }
        }
    }

    private var canSend: Bool {
        !assistant.isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        assistant.send(text)
        // The draft is kept when the question was not sent (no key, or the Assistant is off).
        if assistant.isStreaming { text = "" }
    }
}
