import AppKit
import SwiftUI

struct VaultSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var vaultSession: VaultSession

    var body: some View {
        Form {
            Section("Vault") {
                LabeledContent("Folder") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(vaultDescription).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                        HStack {
                            if case .available(let url) = vaultSession.state {
                                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            }
                            Button(AppCommand.chooseVault.title) { model.chooseVault() }
                        }
                    }
                }
            }
            Section("Daily note") {
                TextField("Folder", text: $preferences.dailyFolder, prompt: Text("vault root"))
                TextField("File name", text: $preferences.dailyFilename, prompt: Text("YYYY-MM-DD"))
                LabeledContent("Today's note") {
                    Text(previewPath).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text(
                    "Tokens: YYYY, MM, DD. The folder is created on demand. Existing files are never renamed or moved."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("Syncing") {
                Text(
                    "To sync, choose a vault inside iCloud Drive, Dropbox, OneDrive, or another synced folder. That service transfers the Markdown files; keep them downloaded on each Mac. External changes are checked every two seconds and when you return to the app, and conflicting edits pause saving and keep recovery copies."
                )
                Text(
                    "Local tasks and settings stay on this Mac. Apple Reminders and Calendar use their Apple accounts. Chat history stays in memory."
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var vaultDescription: String {
        switch vaultSession.state {
        case .notConfigured: return "None selected"
        case .available(let url): return url.path
        case .needsReauthorization: return "Access needs to be granted again"
        case .unavailable(let why): return why
        }
    }

    private var previewPath: String {
        (try? preferences.dailyNoteTemplate.relativePath(for: Date())) ?? "Invalid template"
    }
}
