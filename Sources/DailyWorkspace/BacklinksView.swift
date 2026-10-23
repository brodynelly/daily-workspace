import SwiftUI
import DailyCore

struct BacklinksView: View {
    @EnvironmentObject var state: AppState
    @State private var links: [IndexedNote] = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading) {
            Text("Backlinks").font(.headline)
            if let error { Text(error).foregroundStyle(.secondary) }
            else if links.isEmpty { Text("No incoming links found.").foregroundStyle(.secondary) }
            ForEach(links) { note in
                Button(note.path) { state.openNote(relativePath: note.path) }.buttonStyle(.link)
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 200, idealWidth: 240)
        .task(id: state.noteURL) {
            guard case .available(let root) = state.vaultState, let url = state.noteURL,
                  let path = NoteVault(root: root).relativePath(of: url) else { return }
            links = []
            error = nil
            do {
                links = try await Task.detached { VaultIndex.backlinks(to: path, in: try VaultIndex.scan(root: root)) }.value
            } catch { self.error = error.localizedDescription }
        }
    }
}
