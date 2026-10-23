import SwiftUI

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var chat: ChatService
    @AppStorage("openRouterModel") private var model = ""
    @State private var draft = ""
    @State private var attachNote = false

    init(chat: ChatService) { self.chat = chat }

    var body: some View {
        VStack(spacing: 0) {
            if chat.messages.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "sparkle").font(.system(size: 28)).foregroundStyle(WorkspaceTheme.coral)
                    Text("A little space to think.")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Ask a question, work through an idea, or bring a note into the conversation.")
                        .font(.system(size: 16)).foregroundStyle(.secondary)
                    SettingsLink { Text("Set up OpenRouter →").font(.callout) }
                        .buttonStyle(.plain).foregroundStyle(WorkspaceTheme.coral)
                    Text("Messages go to OpenRouter and its providers. Notes are shared only when attached. API usage may incur charges.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 420, alignment: .leading)
                }
                .frame(maxWidth: 620, maxHeight: .infinity, alignment: .leading)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 30) {
                            ForEach(chat.messages) { message in
                                HStack(alignment: .top) {
                                    if message.role == "user" { Spacer(minLength: 70) }
                                    VStack(alignment: .leading, spacing: 8) {
                                        if message.role != "user" {
                                            Text("Assistant").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(message.content).font(.system(size: 17)).lineSpacing(6).textSelection(.enabled)
                                    }
                                    .padding(message.role == "user" ? 16 : 0)
                                    .background(message.role == "user" ? Color.white.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 20))
                                    if message.role != "user" { Spacer(minLength: 20) }
                                }
                                .frame(maxWidth: 760, alignment: .leading)
                                .id(message.id)
                            }
                        }.padding(32).frame(maxWidth: .infinity)
                    }
                    .onChange(of: chat.messages.count) { _, _ in if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            if let error = chat.error { InfoBanner(text: error) }
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $attachNote) {
                    Label("Attach open note", systemImage: "paperclip")
                }
                .toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
                .disabled(state.noteURL == nil || chat.sending)
                HStack(alignment: .bottom) {
                    TextField("Ask anything…", text: $draft, axis: .vertical).font(.system(size: 17)).lineLimit(1...6).textFieldStyle(.plain).disabled(chat.sending)
                    if chat.sending {
                        ProgressView().controlSize(.small)
                        Button("Stop") { chat.cancel() }
                    } else {
                        Button {
                            chat.send(draft, model: model.trimmingCharacters(in: .whitespaces), note: attachNote ? state.noteText : nil)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 26)).foregroundStyle(WorkspaceTheme.coral)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Send message")
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
            .padding(18).softControlSurface()
            .padding(.horizontal, 24).padding(.bottom, 20)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("AI Chat")
        .toolbar { Button("Clear Chat", systemImage: "trash") { chat.clear() }.disabled(chat.sending) }
        .onChange(of: chat.sending) { _, sending in
            if !sending && chat.error == nil && chat.messages.last?.role == "assistant" { draft = ""; attachNote = false }
        }
    }
}

struct AISettingsView: View {
    @AppStorage("openRouterModel") private var model = ""
    @State private var key = ""
    @State private var status = ""
    var body: some View {
        Form {
            TextField("Model ID", text: $model, prompt: Text("Use OpenRouter account default"))
            SecureField("New API key", text: $key)
            HStack {
                Button("Save Key") {
                    do { try ChatKeychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); key = ""; status = "Key saved in Keychain." }
                    catch { status = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove Key", role: .destructive) {
                    do { try ChatKeychain.save(""); status = "Key removed." }
                    catch { status = error.localizedDescription }
                }
            }
            Text(status).font(.caption)
            Text("Chat uses OpenRouter. Messages are kept in memory for this session. Notes are included only when you attach them. API usage may incur charges.").font(.caption).foregroundStyle(.secondary)
            Link("OpenRouter model IDs and account", destination: URL(string: "https://openrouter.ai/models")!)
        }.formStyle(.grouped)
    }
}
