import SwiftUI

/// Notes: the editor for the open note, and vault search as a mode of the same screen (also ⇧⌘F and ⌘K).
/// Backlinks open in the inspector.
struct NotesView: View {
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var document: NoteDocument
    @State private var showBacklinks = false

    var body: some View {
        NotesPage(showBacklinks: $showBacklinks)
            .navigationTitle(document.url?.deletingPathExtension().lastPathComponent ?? AppSection.notes.title)
            .inspector(isPresented: $showBacklinks) {
                BacklinksView().inspectorColumnWidth(min: 220, ideal: 260, max: 360)
            }
            // Opening a note (from search, the sidebar or a command) shows it.
            .onChange(of: document.url) { _, _ in navigation.notesMode = .editor }
    }
}

/// The Notes page column: the header with its mode, recent-note and view toggles, then the editor or search.
struct NotesPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var vaultSession: VaultSession
    @EnvironmentObject private var document: NoteDocument
    @Binding var showBacklinks: Bool

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
                noNoteOpen
            } else {
                NoteEditorPane()
            }
        } else {
            VaultStatusView(state: vaultSession.state)
        }
    }

    /// No note is open: say so, offer today's note, and list the recent notes as rows.
    private var noNoteOpen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                EmptyState(
                    "No note open", description: "Open today's note, or pick a recent one.",
                    systemImage: "doc.text", boxed: true
                ) {
                    Button(AppCommand.openTodayNote.title) { model.openToday() }
                        .buttonStyle(.primary)
                }
                if let message = document.message { Callout(message) }
                if !preferences.recentNotes.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        SectionHeading("Recent notes")
                        RecordList(variant: .rows) {
                            ForEach(preferences.recentNotes, id: \.self) { path in
                                NoteRecordRow(path: path) { model.openNote(path) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A note as a record row: its title, then its folder muted and whole on its own line (wrapped, never cut),
/// and an optional excerpt. The whole row opens the note.
struct NoteRecordRow: View {
    let path: String
    var excerpt: String?
    let action: () -> Void

    var body: some View {
        RecordRow(action: action) {
            Text(NotePath.title(path))
                .textRole(.body, lineBox: false)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(NotePath.folder(path) ?? "Vault root")
                .textRole(.caption, lineBox: false)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let excerpt, !excerpt.isEmpty {
                // Prose may clamp to two lines; the path above never does.
                Text(excerpt)
                    .textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
            }
        }
        .help(path)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the note")
    }
}
