import DailyCore
import SwiftUI

/// The ⌘J AI chat popup, laid out like Raycast's AI chat: a header with the model, the conversation,
/// a composer, and an action list (⌘K), model list (⇧⌘M) or `/` command list in the corner.
@MainActor
struct QuickPanelAIPopupView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var popup: QuickPanelAIPopup
    @ObservedObject var assistant: AssistantSession
    @ObservedObject var key: AssistantKey
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var preferences: Preferences
    @FocusState private var fieldFocused: Bool
    private typealias Ink = QuickPanelPascalSkin.Ink

    private var isConnected: Bool { preferences.assistantEnabled && key.isSaved }

    var body: some View {
        GeometryReader { geometry in
            let scale = controller.aiZoomScale
            let width = min(860, geometry.size.width - 80) / scale
            let height = min(580, geometry.size.height - 70) / scale
            card
                .frame(width: width, height: height)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black.opacity(0.35))
        .onAppear { focusField() }
        .onChange(of: popup.layer) { _, _ in focusField() }
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Ink.idleRule.opacity(0.35)).frame(height: 1)
            if isConnected {
                conversation
            } else {
                disconnected
            }
            composer
        }
        .background(Ink.titleBox)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Ink.idleRule.opacity(0.6), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) { cornerList }
        .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
        .font(.system(size: 13))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI chat")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                controller.toggleAIPopup()
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.meta)
            .help("Close (esc)")
            VStack(alignment: .leading, spacing: 2) {
                Text(assistant.turns.first?.question ?? assistant.pendingQuestion ?? "New AI Chat")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Button {
                    controller.showModelPicker()
                } label: {
                    HStack(spacing: 4) {
                        Text("\(preferences.assistantProvider.title) · \(preferences.selectedAssistantModel)")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Ink.meta)
                .help("Change model (⇧⌘M)")
            }
            Spacer(minLength: 12)
            if controller.aiZoomScale != 1 {
                Text("\(Int((controller.aiZoomScale * 100).rounded()))%").foregroundStyle(Ink.meta)
                    .font(.system(size: 11, design: .monospaced))
            }
            if assistant.isStreaming {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if assistant.turns.isEmpty && !assistant.isStreaming {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ask about your projects, notes, calendar or agents.")
                                .foregroundStyle(Ink.footer)
                            Text("Type / for commands · ⌘K for actions · ⇧⌘M to change model")
                                .foregroundStyle(Ink.meta).font(.system(size: 11))
                        }
                        .padding(.top, 8)
                    }
                    ForEach(assistant.turns) { turn in
                        exchange(question: turn.question, answer: turn.answer, sources: turn.citations.count)
                    }
                    if assistant.isStreaming {
                        exchange(
                            question: assistant.pendingQuestion ?? "",
                            answer: assistant.liveText.isEmpty ? "Thinking…" : assistant.liveText, sources: 0)
                    }
                    if let error = assistant.error {
                        Text(error).foregroundStyle(Ink.coral).font(.system(size: 12))
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            .onChange(of: assistant.liveText) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: assistant.turns.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .frame(maxHeight: .infinity)
    }

    private func exchange(question: String, answer: String, sources: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 80)
                Text(question)
                    .foregroundStyle(Ink.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Ink.selection, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").foregroundStyle(Ink.gold)
                    Text(preferences.selectedAssistantModel).foregroundStyle(Ink.meta)
                }
                .font(.system(size: 11))
                QuickPanelMarkdownView(text: answer)
                if sources > 0 {
                    Text("\(sources) \(sources == 1 ? "source" : "sources") cited · open in Daily Workspace to inspect")
                        .foregroundStyle(Ink.meta).font(.system(size: 11))
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice = popup.notice {
                Text(notice).foregroundStyle(Ink.cyan).font(.system(size: 11))
            }
            HStack(spacing: 10) {
                Button {
                    controller.newAIChat()
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Ink.header, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.footer)
                .help("New chat (⌘N)")
                TextField("Ask anything, or / for commands…", text: $navigation.assistantDraft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .disabled(!isConnected)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Ink.header, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityLabel("Ask AI")
                QuickPanelKeyCaps(keys: "⇧⌘M", label: "Model")
                QuickPanelKeyCaps(keys: "⌘K", label: "Actions")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Ink.pane)
    }

    private var disconnected: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(Ink.gold)
            Text(
                preferences.assistantEnabled
                    ? "Add an API key in Settings → AI to chat here."
                    : "The Assistant is off. Nothing is sent until you turn it on in Settings → AI."
            )
            .foregroundStyle(Ink.footer)
            .multilineTextAlignment(.center)
            Button("Open Settings → AI") {
                navigation.showSettings(tab: .ai)
                controller.toggleAIPopup()
                controller.open(navigation.section)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.cyan)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    @ViewBuilder private var cornerList: some View {
        switch popup.layer {
        case .actions:
            QuickPanelAIList(
                rows: controller.aiFilteredActions.map {
                    .init(id: $0.id, title: $0.title, symbol: $0.symbol, keys: $0.keys, destructive: $0.destructive)
                },
                selected: popup.listIndex, query: popup.listQuery, placeholder: "Search for actions…",
                status: nil
            ) { index in
                let actions = controller.aiFilteredActions
                guard actions.indices.contains(index) else { return }
                popup.layer = .chat
                actions[index].perform()
            }
        case .models:
            QuickPanelAIList(
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
                    rows: slash.map { .init(id: $0.id, title: $0.title, symbol: $0.symbol, keys: $0.keys) },
                    selected: popup.listIndex, query: nil, placeholder: "", status: nil
                ) { index in
                    if slash.indices.contains(index) { slash[index].perform() }
                }
                .padding(.bottom, 58)
            }
        }
    }

    private func focusField() {
        let wanted = popup.layer == .chat
        DispatchQueue.main.async { fieldFocused = wanted }
    }
}

/// The corner list used for actions, models and `/` commands, styled like Raycast's action panel.
struct QuickPanelAIList: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var keys = ""
        var destructive = false
    }

    let rows: [Row]
    let selected: Int
    let query: String?
    let placeholder: String
    let status: String?
    let run: (Int) -> Void
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if let status {
                            Text(status).foregroundStyle(Ink.meta).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 10) {
                                Image(systemName: row.symbol).frame(width: 18)
                                    .foregroundStyle(row.destructive ? Ink.coral : Ink.cyan)
                                Text(row.title).lineLimit(1)
                                    .foregroundStyle(row.destructive ? Ink.coral : Ink.primary)
                                Spacer(minLength: 8)
                                if !row.keys.isEmpty {
                                    if row.keys.count > 6 {
                                        Text(row.keys).foregroundStyle(Ink.meta).font(.system(size: 10)).lineLimit(1)
                                    } else {
                                        QuickPanelKeyCaps(keys: row.keys.map(String.init).joined(separator: " "))
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(index == selected ? Ink.selection : .clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { run(index) }
                            .id(row.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selected) { _, index in
                    if rows.indices.contains(index) { proxy.scrollTo(rows[index].id) }
                }
            }
            if let query {
                Rectangle().fill(Ink.idleRule.opacity(0.35)).frame(height: 1)
                Text(query.isEmpty ? placeholder : query)
                    .foregroundStyle(query.isEmpty ? Ink.meta : Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
            }
        }
        .frame(width: 380)
        .frame(maxHeight: 330)
        .fixedSize(horizontal: false, vertical: true)
        .background(Ink.titleBox)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Ink.idleRule.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .padding(12)
    }
}
