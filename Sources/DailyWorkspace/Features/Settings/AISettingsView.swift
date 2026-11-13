import DailyCore
import SwiftUI

/// Settings → AI: selected provider, its Keychain-only API key and its model ID.
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
                        "Questions and the notes, tasks and events the Assistant reads are sent to "
                        + (preferences.assistantProvider == .openRouter
                            ? "OpenRouter and its selected model provider." : "Anthropic.")
                ) {
                    Toggle("Enable the Assistant", isOn: $preferences.assistantEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(
                    "Provider",
                    description: "Changing provider starts a new conversation; keys and model choices remain separate."
                ) {
                    Picker("Provider", selection: $preferences.assistantProvider) {
                        ForEach(AssistantProvider.allCases, id: \.self) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }
                keyRow
                SettingsRow(
                    "Model",
                    description:
                        "The \(preferences.assistantProvider.title) model ID. Changing it starts a new conversation.",
                    stacked: true,
                    divider: false
                ) {
                    if preferences.assistantProvider == .anthropic {
                        TextField(
                            "Model ID", text: $preferences.assistantModel,
                            prompt: Text(AssistantSession.defaultModel)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(TextRole.mono.font)
                        .frame(width: 320)
                    } else {
                        TextField(
                            "Model ID", text: $preferences.openRouterModel,
                            prompt: Text(WorkspaceSettings.defaultOpenRouterModel)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(TextRole.mono.font)
                        .frame(width: 320)
                    }
                }
            }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface)
        .onAppear { key.refresh() }
        .onChange(of: preferences.assistantProvider) { _, _ in
            newKey = ""
            keyMessage = nil
            keyFailed = false
        }
    }

    private var keyRow: some View {
        SettingsRow(
            "\(preferences.assistantProvider.title) API key",
            description: preferences.assistantProvider == .anthropic
                ? "Stored only in the macOS Keychain. Claude subscription OAuth cannot authenticate this app."
                : "Stored only in the macOS Keychain, never in a file or the vault.",
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
        if key.isChecking { return "Checking Keychain" }
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
