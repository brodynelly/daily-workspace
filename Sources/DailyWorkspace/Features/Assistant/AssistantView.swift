import DailyCore
import SwiftUI

/// Assistant: questions about notes, projects, open loops and the calendar, answered with cited read-only
/// lookups. Nothing is sent while the Assistant is off or the selected provider has no key.
/// The provider and its model appear in the header so cross-provider routing is always visible.
struct AssistantView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var assistant: AssistantSession
    @EnvironmentObject private var key: AssistantKey
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var navigation: AppNavigation

    @State private var reveal: UUID?

    var body: some View {
        Page(scrolls: false) {
            PageHeader(
                title: AppSection.assistant.title, description: AppSection.assistant.description, meta: meta
            ) {
                if isConnected { actions }
            }
            if isConnected {
                HStack(alignment: .top, spacing: Space.s6) {
                    AssistantRail(reveal: $reveal).frame(width: 280)
                    VerticalHairline()
                    VStack(alignment: .leading, spacing: Space.s3) {
                        AssistantTranscript(reveal: $reveal).frame(maxHeight: .infinity)
                        if let error = assistant.error { AssistantErrorNote(message: error) }
                        if !navigation.showingAssistantPanel {
                            AssistantComposer(text: $navigation.assistantDraft)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: Space.s3) {
                    AssistantConnect()
                    ScrollView { AssistantNativeRuns() }
                }
            }
        }
        .navigationTitle(AppSection.assistant.title)
        .onAppear {
            key.refresh()
            model.syncAssistantVaultAgents()
        }
    }

    private var isConnected: Bool { preferences.assistantEnabled && key.isSaved }

    private var meta: String? {
        guard isConnected else { return nil }
        let chosen = preferences.selectedAssistantModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback =
            preferences.assistantProvider == .anthropic
            ? AssistantSession.defaultModel : WorkspaceSettings.defaultOpenRouterModel
        return "\(preferences.assistantProvider.title) · \(chosen.isEmpty ? fallback : chosen) · read-only tools"
    }

    @ViewBuilder private var actions: some View {
        if assistant.isStreaming {
            Button("Stop", systemImage: "stop.circle") { assistant.stop() }
                .buttonStyle(.workspace(.secondary, size: .large))
                .keyboardShortcut(
                    KeyboardShortcutCatalog.binding(for: "assistant.stop", preferences: preferences)?.menuShortcut
                )
                .help("Stop the answer. The conversation so far is kept as it was.")
        }
        Button("New conversation", systemImage: "plus.bubble") {
            assistant.clear()
            navigation.assistantDraft = ""
        }
        .buttonStyle(.workspace(.secondary, size: .large))
        .disabled(assistant.turns.isEmpty && !assistant.isStreaming && assistant.error == nil)
        .help("Start over with an empty conversation")
    }
}

/// Shown while the Assistant is off or has no key: what is missing, what would be sent, and the one control
/// that fixes it.
struct AssistantConnect: View {
    @EnvironmentObject private var key: AssistantKey
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: Space.s4) {
            EmptyState(title, description: disclosure, systemImage: "lock.shield", boxed: true) {
                Button("Open AI settings") { model.navigation.showSettings(tab: .ai) }
                    .buttonStyle(.primary)
            }
            if let readError = key.readError {
                ReasonNote(readError, tone: .danger, next: "Unlock the login keychain, then open this screen again.")
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s6)
    }

    private var disclosure: String {
        let route =
            preferences.assistantProvider == .openRouter
            ? "OpenRouter and its selected model provider" : "Anthropic"
        return "Questions and the notes, tasks and events the Assistant reads are sent to \(route). "
            + "Nothing is sent until you turn it on and save the selected provider's API key."
    }

    private var title: String {
        if !preferences.assistantEnabled { return "The Assistant is off" }
        if key.isChecking { return "Checking the Keychain" }
        return key.readError == nil
            ? "Add a \(preferences.assistantProvider.title) API key" : "The API key could not be read"
    }
}

/// A failed or refused turn: the reason in the danger tone, then the next step.
struct AssistantErrorNote: View {
    let message: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            ReasonNote(message, tone: .danger, next: Self.nextStep(for: message))
                .frame(maxWidth: .infinity, alignment: .leading)
            if message.contains("Settings → AI") {
                Button("Open AI settings") { model.navigation.showSettings(tab: .ai) }
                    .buttonStyle(.text)
            }
        }
    }

    /// The step after an error. Messages that already name where to go get none.
    static func nextStep(for message: String) -> String? {
        if message.contains("Settings → AI") { return nil }
        if message.contains("declined") { return "Rephrase the question, or ask about something else." }
        return "Ask again. The conversation so far is unchanged."
    }
}
