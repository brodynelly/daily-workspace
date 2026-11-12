import SwiftUI

/// Notes: the editor for the open note, and vault search as a mode of the same screen (also ⇧⌘F and ⌘K).
struct NotesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var vaultSession: VaultSession
    @EnvironmentObject private var document: NoteDocument
    @State private var showBacklinks = false

    var body: some View {
        Page(scrolls: false) {
            PageHeader(title: AppSection.notes.title, description: AppSection.notes.description) {
                headerActions
            }
            Group {
                if navigation.notesMode == .search {
                    SearchView()
                } else {
                    editorArea
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle(document.url?.deletingPathExtension().lastPathComponent ?? AppSection.notes.title)
        .inspector(isPresented: $showBacklinks) { BacklinksView() }
        // Opening a note (from search, the sidebar or a command) shows it.
        .onChange(of: document.url) { _, _ in navigation.notesMode = .editor }
    }

    @ViewBuilder private var headerActions: some View {
        SegmentedControl(
            "Notes mode", selection: $navigation.notesMode, options: NotesMode.allCases.map { ($0, $0.title) })
        Menu {
            Button(AppCommand.openTodayNote.title) { model.openToday() }
            if !preferences.recentNotes.isEmpty {
                Divider()
                ForEach(preferences.recentNotes, id: \.self) { path in
                    Button(NotePath.menuTitle(path)) { model.openNote(path) }
                }
            }
        } label: {
            Label("Recent", systemImage: "clock.arrow.circlepath")
        }
        .menuStyle(.button)
        .buttonStyle(.quiet)
        .fixedSize()
        .help("Open today's note or a recent note")
        .disabled(vaultSession.state == .notConfigured)
        if navigation.notesMode == .editor {
            Toggle(isOn: $preferences.showNotePreview) { Label("Preview", systemImage: "eye") }
                .toggleStyle(.quiet)
                .help("Show a live Markdown preview")
            Toggle(isOn: $showBacklinks) { Label("Backlinks", systemImage: "link") }
                .toggleStyle(.quiet)
                .help("Show notes that link to this one")
        }
    }

    @ViewBuilder private var editorArea: some View {
        if case .available = vaultSession.state {
            if document.url == nil {
                ContentUnavailableView {
                    Label("No note open", systemImage: "doc.text")
                } description: {
                    Text("Open today's note, or pick a recent one.")
                } actions: {
                    Button(AppCommand.openTodayNote.title) { model.openToday() }
                        .buttonStyle(.secondary)
                    if let message = document.message { Text(message).font(.caption) }
                }
            } else {
                editor
            }
        } else {
            VaultStatusView(state: vaultSession.state)
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if document.isConflict {
                ConflictBanner()
            } else if let message = document.message {
                InfoBanner(text: message)
            }
            HSplitView {
                MarkdownEditor(
                    text: Binding(get: { document.text }, set: { document.userEdited($0) }),
                    documentID: document.url,
                    preset: preferences.caretPreset,
                    reduceMotion: model.systemReduceMotion
                )
                if preferences.showNotePreview { NotePreviewView(text: document.text).frame(minWidth: 220) }
            }
            Divider()
            statusBar
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(document.relativePath ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("\(document.text.count) characters").monospacedDigit()
            Spacer()
            SaveStatusLabel(state: document.saveState)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
