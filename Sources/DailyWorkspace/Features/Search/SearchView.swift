import DailyCore
import SwiftUI

/// Vault search: note names and contents. Shown as the Search mode of Notes; reachable from ⌘K and ⇧⌘F.
struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var vaultSession: VaultSession
    @State private var query = ""
    @State private var notes: [IndexedNote] = []
    @State private var loading = false
    @State private var scanned = false
    @State private var error: String?

    private var results: [IndexedNote] { VaultIndex.search(query, in: notes) }

    var body: some View {
        Group {
            if case .available = vaultSession.state {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        SearchField("Search note names and contents", text: $query)
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                            .buttonStyle(.quiet)
                            .help("Rescan the vault after external changes")
                            .disabled(loading)
                        if loading { ProgressView().controlSize(.small) }
                    }
                    if let error { InfoBanner(text: error) }
                    List(results) { note in
                        Button {
                            navigation.notesMode = .editor
                            model.openNote(note.path)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                NoteLabel(path: note.path).font(.headline)
                                Text(note.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                    .overlay { emptyState }
                }
            } else {
                VaultStatusView(state: vaultSession.state)
            }
        }
        .task { await refresh() }
    }

    @ViewBuilder private var emptyState: some View {
        if !loading && scanned && error == nil {
            if notes.isEmpty {
                ContentUnavailableView(
                    "No Markdown notes", systemImage: "doc.text.magnifyingglass",
                    description: Text("The vault has no visible .md files. Click Refresh after adding notes."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func refresh() async {
        guard case .available(let root) = vaultSession.state else { return }
        loading = true
        error = nil
        defer {
            loading = false
            scanned = true
        }
        do {
            notes = try await Task.detached { try VaultIndex.scan(root: root) }.value
        } catch {
            self.error = error.localizedDescription
        }
    }
}
