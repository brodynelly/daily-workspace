import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Form {
            Section("Folder-based vault sync") {
                Text("Select a vault inside iCloud Drive, Dropbox, OneDrive, or your existing synced folder. That service handles transfers; Daily Workspace reads and writes the same Markdown files.")
                Button("Choose Synced Vault…") { state.chooseVault() }
                if case .available(let url) = state.vaultState {
                    Text(url.path).font(.caption).textSelection(.enabled)
                    Button("Reveal Vault in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            Section("Conflicts and availability") {
                Text("Keep files downloaded on each Mac. External changes are checked every two seconds and when you return to the app. Conflicting note edits pause saving and keep recovery copies when resolved.")
                Text("Local Tasks and settings stay on this Mac. Apple Reminders and Calendar use their configured Apple accounts. Chat history stays in memory.")
            }
        }.formStyle(.grouped)
    }
}
