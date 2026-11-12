import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var vaultSession: VaultSession
    @EnvironmentObject private var document: NoteDocument
    @State private var showBacklinks = false

    var body: some View {
        Group {
            if case .available = vaultSession.state {
                if document.url == nil {
                    ContentUnavailableView {
                        Label("No note open", systemImage: "doc.text")
                    } description: {
                        Text("Open today's note, or pick a recent one.")
                    } actions: {
                        Button(AppCommand.openTodayNote.title) { model.openToday() }
                        if let message = document.message { Text(message).font(.caption) }
                    }
                } else {
                    editor
                }
            } else {
                VaultStatusView(state: vaultSession.state)
            }
        }
        .navigationTitle(document.url?.deletingPathExtension().lastPathComponent ?? "Notes")
        .inspector(isPresented: $showBacklinks) { BacklinksView() }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $preferences.showNotePreview) { Label("Preview", systemImage: "eye") }
                    .help("Show a live Markdown preview")
                Toggle(isOn: $showBacklinks) { Label("Backlinks", systemImage: "link") }
                    .help("Show notes that link to this one")
            }
            ToolbarItem {
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
                .help("Open today's note or a recent note")
                .disabled(vaultSession.state == .notConfigured)
            }
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
