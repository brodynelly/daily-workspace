import DailyCore
import SwiftUI

/// Inspector listing notes that link to the open note, as record rows.
struct BacklinksView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vaultSession: VaultSession
    @EnvironmentObject private var document: NoteDocument
    @State private var links: [IndexedNote] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading("Backlinks", description: "Notes that link to this one.")
                if let error {
                    ReasonNote(error, tone: .danger)
                } else if links.isEmpty && !loading {
                    EmptyState("No incoming links", boxed: true)
                }
                RecordList(variant: .rows) {
                    ForEach(links) { note in
                        NoteRecordRow(path: note.path) { model.openNote(note.path) }
                    }
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface)
        .task(id: document.url) {
            guard case .available(let root) = vaultSession.state, let path = document.relativePath else { return }
            links = []
            error = nil
            loading = true
            defer { loading = false }
            do {
                links = try await Task.detached { VaultIndex.backlinks(to: path, in: try VaultIndex.scan(root: root)) }
                    .value
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
