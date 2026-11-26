import DailyCore
import SwiftUI

/// ⌘J / `?`: the AI chat takes over the panel's panes, in the panel's own style. CHATS lists the current and
/// earlier chats (⌘[ / ⌘] step between them), AI CHAT shows the answers, ASK is the composer.
extension QuickPanelPascalSkin {
    @ViewBuilder func aiPage(width: CGFloat, height: CGFloat) -> some View {
        if let model = controller.model {
            let left = round(min(300, width * 0.26))
            let x = left + 15
            let contentWidth = max(0, width - x - 7)
            pane("CHATS", active: controller.aiPopup.section == .chats) {
                QuickPanelAIChatsView(
                    controller: controller, popup: controller.aiPopup, assistant: model.assistant,
                    preferences: model.preferences)
            }
            .frame(width: left, height: max(0, height - 78))
            .offset(x: 7, y: 40)
            pane("AI CHAT.PAS", active: controller.aiPopup.section == .conversation) {
                QuickPanelAIConversationView(
                    controller: controller, popup: controller.aiPopup, assistant: model.assistant,
                    key: model.assistantKey, navigation: model.navigation, preferences: model.preferences)
            }
            .frame(width: contentWidth, height: max(0, height - 78 - 96))
            .offset(x: x, y: 40)
            pane("ASK", active: controller.aiPopup.section == .ask) {
                QuickPanelAIComposerView(
                    controller: controller, popup: controller.aiPopup, assistant: model.assistant,
                    key: model.assistantKey, navigation: model.navigation, preferences: model.preferences)
            }
            .frame(width: contentWidth, height: 84)
            .offset(x: x, y: height - 122)
        } else {
            pane("AI CHAT.PAS", active: true) {
                Text("The Assistant is unavailable.").foregroundStyle(Ink.meta)
            }
            .frame(width: width - 14, height: max(0, height - 78))
            .offset(x: 7, y: 40)
        }
    }
}

/// The left pane: the current chat and earlier chats from this app run, then the provider and model.
@MainActor
struct QuickPanelAIChatsView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var popup: QuickPanelAIPopup
    @ObservedObject var assistant: AssistantSession
    @ObservedObject var preferences: Preferences
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        row(
                            0, title: assistant.turns.first?.question ?? assistant.pendingQuestion ?? "New chat",
                            detail: "current · \(answers(assistant.turns.count))", current: true)
                        if !popup.chats.isEmpty {
                            Text("EARLIER").foregroundStyle(Ink.cyan).panelFont(10)
                                .padding(.top, 8).padding(.horizontal, 6)
                        }
                        ForEach(Array(popup.chats.enumerated()), id: \.element.id) { index, chat in
                            row(
                                index + 1, title: chat.title,
                                detail: "\(answers(chat.turns.count)) · \(Self.age(chat.archivedAt))"
                                    + (chat.model == preferences.selectedAssistantModel ? "" : " · \(chat.model)"),
                                current: false)
                        }
                    }
                }
                .onChange(of: popup.chatIndex) { _, index in proxy.scrollTo(index) }
            }
            Rectangle().fill(Ink.idleRule.opacity(0.4)).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(preferences.assistantProvider.title.uppercased()).foregroundStyle(Ink.cyan)
                Button {
                    controller.showModelPicker()
                } label: {
                    Text(preferences.selectedAssistantModel).foregroundStyle(Ink.title).lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Change model (⇧⌘M)")
                Text("chats stay until the app quits").foregroundStyle(Ink.meta)
            }
            .panelFont(11)
        }
    }

    private func row(_ index: Int, title: String, detail: String, current: Bool) -> some View {
        let selected = popup.section == .chats && popup.chatIndex == index
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if current { Circle().fill(Ink.gold).frame(width: 5, height: 5) }
                Text(title).lineLimit(1).foregroundStyle(selected || current ? Ink.title : Ink.primary)
            }
            Text(detail).lineLimit(1).foregroundStyle(Ink.meta).panelFont(10.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pascalSelection(selected)
        .contentShape(Rectangle())
        .id(index)
        .onTapGesture {
            popup.section = .chats
            popup.chatIndex = index
            controller.openAIChatRow(index)
        }
    }

    private func answers(_ count: Int) -> String { "\(count) \(count == 1 ? "answer" : "answers")" }

    static func age(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        let now = Date()
        return now.timeIntervalSince(date) < 60
            ? "just now" : formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}

/// The conversation: each question, then the answer as rendered Markdown.
@MainActor
struct QuickPanelAIConversationView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var popup: QuickPanelAIPopup
    @ObservedObject var assistant: AssistantSession
    @ObservedObject var key: AssistantKey
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var preferences: Preferences
    private typealias Ink = QuickPanelPascalSkin.Ink

    private var isConnected: Bool { preferences.assistantEnabled && key.isSaved }

    var body: some View {
        Group {
            if isConnected {
                transcript
            } else {
                disconnected
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) { cornerList }
        .panelFont(13)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if assistant.turns.isEmpty && !assistant.isStreaming {
                        intro
                    }
                    ForEach(Array(assistant.turns.enumerated()), id: \.element.id) { index, turn in
                        exchange(turn.question, turn.answer, sources: turn.citations.count)
                            .id(index)
                    }
                    if assistant.isStreaming {
                        exchange(
                            assistant.pendingQuestion ?? "",
                            assistant.liveText.isEmpty ? "Thinking…" : assistant.liveText, sources: 0)
                    }
                    if let error = assistant.error {
                        Text(error).foregroundStyle(Ink.coral)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .onChange(of: assistant.liveText) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: assistant.turns.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: popup.focusedTurn) { _, turn in
                if let turn { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(turn, anchor: .top) } }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about your projects, notes, calendar or agents.").foregroundStyle(Ink.footer)
            HStack(spacing: 14) {
                QuickPanelKeyCaps(keys: "/", label: "Commands")
                QuickPanelKeyCaps(keys: "⌘K", label: "Actions")
                QuickPanelKeyCaps(keys: "⇧⌘M", label: "Model")
                QuickPanelKeyCaps(keys: "⌘[ ⌘]", label: "Chats")
                QuickPanelKeyCaps(keys: "⌃h ⌃j ⌃k ⌃l", label: "Sections")
            }
            .panelFont(11)
        }
        .padding(.top, 6)
    }

    private func exchange(_ question: String, _ answer: String, sources: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(">").foregroundStyle(Ink.gold)
                Text(question).foregroundStyle(Ink.title).fixedSize(horizontal: false, vertical: true)
            }
            .panelFont(13, weight: .medium)
            VStack(alignment: .leading, spacing: 6) {
                QuickPanelMarkdownView(text: answer)
                if sources > 0 {
                    Text("\(sources) \(sources == 1 ? "source" : "sources") cited · open in Daily Workspace to inspect")
                        .foregroundStyle(Ink.meta).panelFont(11)
                }
            }
            .padding(.leading, 16)
            .overlay(alignment: .leading) { Rectangle().fill(Ink.idleRule.opacity(0.35)).frame(width: 1) }
        }
    }

    private var disconnected: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                preferences.assistantEnabled
                    ? "Add an API key in Settings → AI to chat here."
                    : "The Assistant is off. Nothing is sent until you turn it on in Settings → AI."
            )
            .foregroundStyle(Ink.footer)
            Button("Open Settings → AI") {
                navigation.showSettings(tab: .ai)
                controller.toggleAIPopup()
                controller.open(navigation.section)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.cyan)
        }
        .padding(8)
    }

    @ViewBuilder private var cornerList: some View {
        switch popup.layer {
        case .actions:
            QuickPanelAIList(
                title: "ACTIONS",
                rows: controller.aiFilteredActions.map {
                    .init(id: $0.id, title: $0.title, symbol: $0.symbol, keys: $0.keys, destructive: $0.destructive)
                },
                selected: popup.listIndex, query: popup.listQuery, placeholder: "Search for actions…", status: nil
            ) { index in
                let actions = controller.aiFilteredActions
                guard actions.indices.contains(index) else { return }
                popup.layer = .chat
                actions[index].perform()
            }
        case .models:
            QuickPanelAIList(
                title: "MODELS",
                rows: controller.aiModelOptions.map { option in
                    .init(
                        id: option.id, title: option.name,
                        symbol: option.id == preferences.selectedAssistantModel ? "checkmark" : "cpu",
                        keys: option.name == option.id ? "" : option.id)
                },
                selected: popup.listIndex, query: popup.listQuery, placeholder: "Search models…",
                status: popup.modelsStatus
            ) { index in
                let options = controller.aiModelOptions
                if options.indices.contains(index) { controller.selectModel(options[index]) }
            }
        case .chat:
            let slash = controller.aiSlashActions
            if !slash.isEmpty {
                QuickPanelAIList(
                    title: "COMMANDS",
                    rows: slash.map { .init(id: $0.id, title: $0.title, symbol: $0.symbol, keys: $0.keys) },
                    selected: popup.listIndex, query: nil, placeholder: "", status: nil
                ) { index in
                    if slash.indices.contains(index) { slash[index].perform() }
                }
            }
        }
    }
}

/// The ASK pane: the shared draft. Return asks; `/` shows commands.
@MainActor
struct QuickPanelAIComposerView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var popup: QuickPanelAIPopup
    @ObservedObject var assistant: AssistantSession
    @ObservedObject var key: AssistantKey
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var preferences: Preferences
    @FocusState private var fieldFocused: Bool
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Text(">").foregroundStyle(Ink.title)
                TextField("Ask anything, or / for commands…", text: $navigation.assistantDraft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .disabled(!(preferences.assistantEnabled && key.isSaved))
                    .accessibilityLabel("Ask AI")
                if assistant.isStreaming { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 12) {
                if let notice = popup.notice {
                    Text(notice).foregroundStyle(Ink.cyan)
                } else {
                    Text("\(preferences.assistantProvider.title) · \(preferences.selectedAssistantModel)")
                        .foregroundStyle(Ink.meta)
                }
            }
            .panelFont(11)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { focus() }
        .onChange(of: popup.layer) { _, _ in focus() }
        .onChange(of: popup.section) { _, _ in focus() }
    }

    private func focus() {
        let wanted = popup.layer == .chat && popup.section == .ask
        DispatchQueue.main.async { fieldFocused = wanted }
    }
}
