import SwiftUI

/// Settings → AI: the Assistant's switch, its Anthropic API key (Keychain only) and the model ID.
struct AISettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var key: AssistantKey

    @State private var newKey = ""
    @State private var keyMessage: String?
    @State private var keyFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Assistant")
                    .padding(.bottom, Space.s1)
                SettingsRow(
                    "Enable the Assistant",
                    description:
                        "Questions and the notes, tasks and events the Assistant reads are sent to Anthropic."
                ) {
                    Toggle("Enable the Assistant", isOn: $preferences.assistantEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                keyRow
                SettingsRow(
                    "Model",
                    description: "The Anthropic model ID. Changing it starts a new conversation.",
                    stacked: true,
                    divider: false
                ) {
                    TextField(
                        "Model ID", text: $preferences.assistantModel,
                        prompt: Text(AssistantSession.defaultModel)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(TextRole.mono.font)
                    .frame(width: 320)
                }
            }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface)
        .onAppear { key.refresh() }
    }

    private var keyRow: some View {
        SettingsRow(
            "Anthropic API key",
            description: "Stored only in the macOS Keychain, never in a file or the vault.",
            stacked: true
        ) {
            StatusBadge(keyStatus, tone: key.readError == nil ? nil : .danger)
        } control: {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    SecureField(key.isSaved ? "Replace the saved key" : "API key", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                        .onSubmit(saveKey)
                    Button(key.isSaved ? "Replace" : "Save", action: saveKey)
                        .buttonStyle(.primary)
                        .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove", action: removeKey)
                        .buttonStyle(.secondary)
                        .disabled(!key.isSaved)
                }
                if let readError = key.readError {
                    ReasonNote(readError, tone: .danger, next: "Unlock the login keychain, then reopen Settings.")
                } else if let keyMessage {
                    if keyFailed {
                        ReasonNote(keyMessage, tone: .danger)
                    } else {
                        Text(keyMessage).textRole(.bodySmall, lineBox: false).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }

    private var keyStatus: String {
        if key.readError != nil { return "Unreadable" }
        return key.isSaved ? "Saved" : "Not set"
    }

    private func saveKey() {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try key.save(trimmed)
            newKey = ""
            keyFailed = false
            keyMessage = "The key is saved in the Keychain."
        } catch {
            keyFailed = true
            keyMessage = "The key could not be saved in the Keychain: \(error.localizedDescription)"
        }
    }

    private func removeKey() {
        do {
            try key.remove()
            keyFailed = false
            keyMessage = "The key was removed from the Keychain."
        } catch {
            keyFailed = true
            keyMessage = "The key could not be removed: \(error.localizedDescription)"
        }
    }
}
