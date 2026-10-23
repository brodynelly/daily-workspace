import SwiftUI
import DailyCore

struct NoteBrowserView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var notes: [IndexedNote] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if loading { ProgressView().controlSize(.small).padding() }
            if let error { InfoBanner(text: error) }
            List(VaultIndex.search(query, in: notes)) { note in
                Button {
                    state.openNote(relativePath: note.path)
                    state.section = .notes
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title).font(.headline)
                        Text(note.path).font(.caption).foregroundStyle(.secondary)
                        Text(note.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if !loading && notes.isEmpty { ContentUnavailableView("No notes indexed", systemImage: "doc.text.magnifyingglass", description: Text("Choose a vault in Settings, then refresh.")) }
            }
        }
        .searchable(text: $query, prompt: "Search note names and contents")
        .navigationTitle("Search")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }.disabled(loading) }
        .task { await refresh() }
    }

    private func refresh() async {
        guard case .available(let root) = state.vaultState else { return }
        loading = true
        error = nil
        defer { loading = false }
        do { notes = try await Task.detached { try VaultIndex.scan(root: root) }.value }
        catch { self.error = error.localizedDescription }
    }
}
