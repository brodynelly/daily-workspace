import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject private var chat: ChatService
    @EnvironmentObject private var preferences: Preferences
    @State private var key = ""
    @State private var status: String?

    var body: some View {
        Form {
            TextField("Model ID", text: $preferences.openRouterModel, prompt: Text("Use OpenRouter account default"))
            LabeledContent("API key") {
                Text(chat.keyStatusError ?? (chat.hasAPIKey ? "Saved in Keychain" : "Not set"))
                    .foregroundStyle(.secondary)
            }
            SecureField(chat.hasAPIKey ? "Replace API key" : "API key", text: $key)
            HStack {
                Button(chat.hasAPIKey ? "Replace Key" : "Save Key") {
                    update(to: key, done: "Key saved in Keychain.")
                }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove Key", role: .destructive) { update(to: "", done: "Key removed.") }
                    .disabled(!chat.hasAPIKey)
            }
            if let status { Text(status).font(.caption) }
            Text(
                "Chat uses OpenRouter. Messages are kept in memory for this session. Notes are included only when you attach them. API usage may incur charges."
            )
            .font(.caption).foregroundStyle(.secondary)
            Link("OpenRouter model IDs and account", destination: URL(string: "https://openrouter.ai/models")!)
        }
        .formStyle(.grouped)
        .onAppear { chat.refreshKeyStatus() }
    }

    private func update(to newKey: String, done: String) {
        do {
            try chat.saveKey(newKey)
            key = ""
            status = done
        } catch {
            status = error.localizedDescription
        }
    }
}
