import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var chat: ChatService
    @EnvironmentObject private var document: NoteDocument
    @EnvironmentObject private var preferences: Preferences
    @State private var draft = ""
    @State private var attachNote = false

    var body: some View {
        VStack(spacing: 0) {
            if chat.messages.isEmpty {
                emptyState
            } else {
                transcript
            }
            if let error = chat.error { InfoBanner(text: error) }
            composer
        }
        .navigationTitle(AppSection.chat.title)
        .toolbar {
            Button("Clear Chat", systemImage: "trash") { chat.clear() }
                .disabled(chat.sending || chat.messages.isEmpty)
        }
        .onAppear { chat.refreshKeyStatus() }
        .onChange(of: chat.sending) { _, sending in
            if !sending && chat.error == nil && chat.messages.last?.role == .assistant {
                draft = ""
                attachNote = false
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "sparkle").font(.largeTitle).foregroundStyle(.tint)
            Text("A little space to think.")
                .font(.title.bold())
            Text("Ask a question, work through an idea, or bring a note into the conversation.")
                .font(.title3).foregroundStyle(.secondary)
            if !chat.hasAPIKey {
                SettingsLink { Text("Add an OpenRouter Key in Settings…") }
            }
            Text(
                "Messages go to OpenRouter and its providers. Notes are shared only when attached. API usage may incur charges."
            )
            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 420, alignment: .leading)
        }
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(chat.messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: chat.messages.count) { _, _ in
                if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $attachNote) {
                Label("Attach Open Note", systemImage: "paperclip")
            }
            .toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
            .disabled(document.url == nil || chat.sending)
            HStack(alignment: .bottom) {
                TextField("Ask anything…", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .disabled(chat.sending)
                if chat.sending {
                    ProgressView().controlSize(.small)
                    Button("Stop") { chat.cancel() }
                } else {
                    Button {
                        chat.send(
                            draft, model: preferences.openRouterModel, note: attachNote ? document.text : nil)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send message")
                    .help("Send (⌘↩)")
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(12).softControlSurface(radius: 12)
        .padding(.horizontal, 20).padding(.bottom, 16)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == .user
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 70) }
            VStack(alignment: .leading, spacing: 8) {
                if !isUser {
                    Text("Assistant").font(.caption).foregroundStyle(.secondary)
                }
                Text(message.content).font(.body).lineSpacing(3).textSelection(.enabled)
            }
            .padding(isUser ? 12 : 0)
            .background(
                isUser ? WorkspaceTheme.recessed : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !isUser { Spacer(minLength: 20) }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}
