import DailyCore
import SwiftUI

/// Inspector listing notes that link to the open note.
struct BacklinksView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vaultSession: VaultSession
    @EnvironmentObject private var document: NoteDocument
    @State private var links: [IndexedNote] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Backlinks").font(.headline)
            if let error {
                Text(error).foregroundStyle(.secondary)
            } else if links.isEmpty {
                Text("No incoming links found.").foregroundStyle(.secondary)
            }
            ForEach(links) { note in
                Button {
                    model.openNote(note.path)
                } label: {
                    NoteLabel(path: note.path)
                }
                .buttonStyle(.link)
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 200, idealWidth: 240)
        .task(id: document.url) {
            guard case .available(let root) = vaultSession.state, let path = document.relativePath else { return }
            links = []
            error = nil
            do {
                links = try await Task.detached { VaultIndex.backlinks(to: path, in: try VaultIndex.scan(root: root)) }
                    .value
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
