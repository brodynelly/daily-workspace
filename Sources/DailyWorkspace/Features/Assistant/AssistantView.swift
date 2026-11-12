import SwiftUI

/// Assistant: the existing chat under the screen's page header. The grounded, tool-using Assistant
/// (SYSTEM-INVENTORY §4–§7, Increment 2) replaces the body later.
struct AssistantView: View {
    @EnvironmentObject private var chat: ChatService

    var body: some View {
        Page(scrolls: false) {
            PageHeader(title: AppSection.assistant.title, description: AppSection.assistant.description) {
                Button("Clear Chat", systemImage: "trash") { chat.clear() }
                    .buttonStyle(.quiet)
                    .disabled(chat.sending || chat.messages.isEmpty)
                    .help("Clear the conversation")
            }
            ChatView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
