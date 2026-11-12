import DailyCore
import SwiftUI

/// Vault search: note names and contents. Shown as the Search mode of Notes; reachable from ⌘K and ⇧⌘F.
/// Results are record rows: the title, the folder muted and whole, and a two-line excerpt.
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
                    if let error { ReasonNote(error, tone: .danger) }
                    if scanned && !notes.isEmpty {
                        Text(countLine)
                            .textRole(.caption, lineBox: false)
                            .foregroundStyle(Theme.inkMuted)
                            .monospacedDigit()
                    }
                    resultList
                }
            } else {
                VaultStatusView(state: vaultSession.state)
            }
        }
        .task { await refresh() }
    }

    private var countLine: String {
        let shown = results.count
        return query.isEmpty ? "\(notes.count) notes" : "\(shown) of \(notes.count) notes match"
    }

    /// Lazy rows: a vault can hold thousands of notes.
    @ViewBuilder private var resultList: some View {
        if !loading && scanned && error == nil && (notes.isEmpty || results.isEmpty) {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { note in
                        NoteRecordRow(path: note.path, excerpt: excerpt(note)) {
                            navigation.notesMode = .editor
                            model.openNote(note.path)
                        }
                    }
                }
                .environment(\.recordListVariant, .rows)
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if notes.isEmpty {
            EmptyState(
                "No Markdown notes", description: "The vault has no visible .md files. Refresh after adding notes.",
                systemImage: "doc.text.magnifyingglass", boxed: true)
        } else {
            EmptyState(
                "No notes match", description: "Nothing in the vault contains “\(query)”.",
                systemImage: "magnifyingglass", boxed: true)
        }
    }

    private func excerpt(_ note: IndexedNote) -> String {
        String(note.text.prefix(400)).replacingOccurrences(of: "\n", with: " ")
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
