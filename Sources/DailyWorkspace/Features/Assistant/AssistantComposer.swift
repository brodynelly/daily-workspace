import AppKit
import SwiftUI

/// The question field and its configurable Ask shortcut. Disabled while an answer or draft is running.
struct AssistantComposer: View {
    @EnvironmentObject private var assistant: AssistantSession
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @Binding var text: String

    @FocusState private var focused: Bool
    @StateObject private var voice = AssistantVoiceService()
    @State private var lastDictationText = ""
    @State private var lastSeenTurn: UUID?
    var autoFocus = false

    var body: some View {
        let submitShortcut = KeyboardShortcutCatalog.binding(for: "assistant.submit", preferences: preferences)
        VStack(alignment: .leading, spacing: Space.s2) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(TextRole.body.font)
                    .foregroundStyle(assistant.isStreaming ? Theme.inkDisabled : Theme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .onAppear { if autoFocus { focused = true } }
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
                Button(voice.isListening || voice.isRequestingPermission ? "Stop dictation" : "Dictate question") {
                    if voice.isListening || voice.isRequestingPermission {
                        voice.stopDictation()
                    } else {
                        lastDictationText = ""
                        voice.startDictation()
                    }
                }
                .disabled(assistant.isStreaming || !assistant.isEnabled)
                .accessibilityLabel(
                    voice.isListening || voice.isRequestingPermission
                        ? "Stop on-device dictation" : "Start on-device dictation")
                Toggle(
                    "Speak finished replies",
                    isOn: Binding(
                        get: { voice.speaksReplies },
                        set: { voice.setSpeaksReplies($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(!assistant.isEnabled)
            }
            Text("Microphone dictation stays on device. Review and press Ask to send. Spoken replies use macOS speech.")
                .textRole(.caption, lineBox: false)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if voice.isListening {
                Text("Listening on this Mac… Tap Stop dictation to turn off the microphone.")
                    .textRole(.caption, lineBox: false)
                    .accessibilityAddTraits(.updatesFrequently)
            } else if voice.isRequestingPermission {
                Text("Waiting for microphone and Speech Recognition permission…")
                    .textRole(.caption, lineBox: false)
            }
            if let error = voice.error {
                Text(error)
                    .textRole(.caption, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .accessibilityLabel(error)
            }
            HStack(spacing: Space.s3) {
                Text(
                    "Questions and the sources read to answer them are sent to "
                        + (preferences.assistantProvider == .openRouter
                            ? "OpenRouter and its selected model provider." : "Anthropic.")
                )
                .textRole(.caption, lineBox: false)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s3)
                if let submitShortcut { Kbd(KeyboardShortcutCatalog.label(for: submitShortcut)) }
                Button("Ask", action: send)
                    .buttonStyle(.primary)
                    .keyboardShortcut(submitShortcut?.menuShortcut)
                    .disabled(!canSend)
            }
        }
        .onAppear { lastSeenTurn = assistant.turns.last?.id }
        .onDisappear { voice.stop() }
        .onChange(of: voice.recognizedText) { _, recognized in
            guard !recognized.isEmpty else { return }
            text = AssistantVoiceService.draft(text, replacing: lastDictationText, with: recognized)
            lastDictationText = recognized
        }
        .onChange(of: assistant.turns.last?.id) { _, id in
            guard let id, id != lastSeenTurn else { return }
            lastSeenTurn = id
            if let answer = assistant.turns.last?.finalAnswer { voice.speakAnswer(answer) }
        }
        .onChange(of: assistant.isEnabled) { _, enabled in
            if !enabled { voice.stop() }
        }
        .onChange(of: assistant.isStreaming) { _, streaming in
            if streaming { voice.stopDictation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if voice.isListening { voice.stopDictation() }
        }
    }

    private var canSend: Bool {
        !assistant.isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        assistant.send(text, pageFocus: AssistantPageFocus.current(section: navigation.section, model: model))
        // The draft is kept when the question was not sent (no key, or the Assistant is off).
        if assistant.isStreaming { text = "" }
    }
}
