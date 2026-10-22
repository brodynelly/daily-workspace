import SwiftUI

struct NotesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            switch state.vaultState {
            case .available:
                if state.noteURL == nil {
                    ContentUnavailableView {
                        Label("No note open", systemImage: "doc.text")
                    } description: {
                        Text("Open today's note, or pick a recent one.")
                    } actions: {
                        Button("Open Today's Note") { state.openToday() }
                        if let message = state.noteMessage { Text(message).font(.caption) }
                    }
                } else {
                    editor
                }
            case .notConfigured:
                ContentUnavailableView {
                    Label("No vault selected", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Choose the folder of your Obsidian vault. Notes stay plain Markdown files there.")
                } actions: {
                    Button("Choose Vault…") { state.chooseVault() }
                }
            case .needsReauthorization:
                ContentUnavailableView {
                    Label("Vault access needed", systemImage: "lock")
                } description: {
                    Text("macOS no longer lets the app open the vault. Choose the folder again to restore access.")
                } actions: {
                    Button("Choose Vault…") { state.chooseVault() }
                }
            case .unavailable(let why):
                ContentUnavailableView {
                    Label("Vault unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(why)
                } actions: {
                    Button("Choose Vault…") { state.chooseVault() }
                }
            }
        }
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Today's Note") { state.openToday() }
                    if !state.recentNotes.isEmpty {
                        Divider()
                        ForEach(state.recentNotes, id: \.self) { path in
                            Button(path) { state.openNote(relativePath: path) }
                        }
                    }
                } label: {
                    Label("Notes", systemImage: "clock.arrow.circlepath")
                }
                .help("Open today's or a recent note")
                .disabled(state.vaultState == .notConfigured)
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if state.isConflict { ConflictBanner() }
            else if let message = state.noteMessage {
                InfoBanner(text: message)
            }
            MarkdownEditor(
                text: Binding(get: { state.noteText }, set: { state.userEdited($0) }),
                documentID: state.noteURL,
                preset: state.caretPreset,
                reduceMotion: state.systemReduceMotion
            )
            Divider()
            statusBar
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(state.noteURL?.lastPathComponent ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            SaveStatusLabel(state: state.saveState)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

struct SaveStatusLabel: View {
    let state: AppState.SaveState

    var body: some View {
        switch state {
        case .clean: Label("Saved", systemImage: "checkmark.circle")
        case .dirty: Label("Unsaved changes", systemImage: "circle.dotted")
        case .saving: Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
        case .conflict: Label("Conflict: not saved", systemImage: "exclamationmark.triangle.fill")
        case .failed(let why): Label("Save failed: \(why)", systemImage: "xmark.octagon.fill")
        }
    }
}

struct InfoBanner: View {
    let text: String

    var body: some View {
        HStack {
            Image(systemName: "info.circle")
            Text(text)
            Spacer()
        }
        .font(.callout)
        .padding(10)
        .background(.quaternary)
        .accessibilityElement(children: .combine)
    }
}

struct ConflictBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This note changed outside the app", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text("Saving is paused so nothing is overwritten. Whichever version you don't keep is saved to a recovery folder.")
                .font(.callout)
            HStack {
                Button("Reload From Disk") { state.resolveConflictByReloading() }
                Button("Keep My Version") { state.resolveConflictByKeepingMine() }
                if let folder = RecoveryStore.folder {
                    Button("Show Recovery Folder") { NSWorkspace.shared.open(folder) }
                        .buttonStyle(.link)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}
