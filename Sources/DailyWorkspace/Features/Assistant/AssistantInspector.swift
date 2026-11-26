import DailyCore
import SwiftUI

/// The same read-only conversation as the Assistant screen, kept beside the current page.
/// Page focus is disclosed here and sent only when the user presses Ask.
struct AssistantInspector: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var assistant: AssistantSession
    @EnvironmentObject private var key: AssistantKey
    @EnvironmentObject private var preferences: Preferences
    @State private var reveal: UUID?

    private var isConnected: Bool { preferences.assistantEnabled && key.isSaved }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "sparkles")
                    .iconRole(.leading)
                    .foregroundStyle(Theme.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Ask AI").textRole(.sectionTitle, lineBox: false)
                    Text("On \(navigation.section.title)\(detail)")
                        .textRole(.caption, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .textSelection(.enabled)
                }
                Spacer(minLength: Space.s1)
                Button {
                    navigation.showingAssistantPanel = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.quiet)
                .accessibilityLabel("Close AI Sidebar")
                .help("Close AI Sidebar")
            }
            Text("The page focus is sent only when you Ask. Read-only lookups verify sources before answering.")
                .textRole(.caption, lineBox: false)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if isConnected {
                HStack(spacing: Space.s2) {
                    Text("\(preferences.assistantProvider.title) · \(preferences.selectedAssistantModel)")
                        .textRole(.caption, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                        .help("Selected provider and model; change them in Settings → AI")
                    Spacer(minLength: 0)
                    if assistant.isStreaming {
                        Button("Stop", systemImage: "stop.circle") { assistant.stop() }
                            .buttonStyle(.quiet)
                            .keyboardShortcut(
                                KeyboardShortcutCatalog.binding(for: "assistant.stop", preferences: preferences)?
                                    .menuShortcut)
                    }
                    Button {
                        assistant.clear()
                        navigation.assistantDraft = ""
                    } label: {
                        Image(systemName: "plus.bubble")
                    }
                    .buttonStyle(.quiet)
                    .accessibilityLabel("New conversation")
                    .disabled(assistant.turns.isEmpty && !assistant.isStreaming && assistant.error == nil)
                }
                Hairline()
                AssistantTranscript(reveal: $reveal)
                    .frame(maxHeight: .infinity)
                if assistant.turns.isEmpty && !assistant.isStreaming && navigation.assistantDraft.isEmpty {
                    Button(suggestedQuestion) { navigation.assistantDraft = suggestedQuestion }
                        .buttonStyle(.text)
                        .help("Fill the question without sending it")
                }
                if let error = assistant.error { AssistantErrorNote(message: error) }
                AssistantComposer(text: $navigation.assistantDraft, autoFocus: true)
            } else {
                ScrollView { AssistantConnect() }
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(Space.s4)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
        .onAppear {
            key.refresh()
            model.syncAssistantVaultAgents()
        }
    }

    private var detail: String {
        switch navigation.section {
        case .calendar: return " · \(LocalDay(model.calendar.selectedDay))"
        case .projects: return model.projects.detail == nil ? "" : " · Selected project"
        case .notes: return model.document.relativePath == nil ? "" : " · Open note"
        default: return ""
        }
    }

    private var suggestedQuestion: String {
        switch navigation.section {
        case .today: return "What needs my attention today?"
        case .projects: return "What is the current state of this project?"
        case .openLoops: return "What is still open across my sources?"
        case .notes: return "What does the open note say about this topic?"
        case .calendar: return "What is on my calendar for the selected day?"
        case .assistant: return "What changed since my last project session?"
        }
    }
}
