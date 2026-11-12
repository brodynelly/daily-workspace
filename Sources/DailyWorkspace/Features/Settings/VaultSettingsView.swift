import AppKit
import DailyCore
import SwiftUI

struct VaultSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var vaultSession: VaultSession

    var body: some View {
        SettingsPage {
            SettingsGroup(
                "Vault", description: "The Obsidian vault the app reads and writes. Notes stay plain Markdown."
            ) {
                PathSettingsRow("Folder", path: vaultDescription, monospaced: vaultURL != nil, divider: false) {
                    if let url = vaultURL {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.secondary)
                    }
                    Button(AppCommand.chooseVault.title) { model.chooseVault() }
                        .buttonStyle(.secondary)
                }
            }
            DailyNoteSettings()
            SettingsGroup("App data") {
                PathSettingsRow("Folder", path: model.directory.url.path, divider: false) {
                    Button("Show in Finder") { NSWorkspace.shared.open(model.directory.url) }
                        .buttonStyle(.secondary)
                }
                SettingsNote(
                    "settings.json, tasks.json and recovery copies of notes live here. Your API key stays in the macOS Keychain."
                )
            }
            SettingsGroup("Syncing") {
                SettingsNote(
                    "To sync, choose a vault inside iCloud Drive, Dropbox, OneDrive, or another synced folder. That service transfers the Markdown files; keep them downloaded on each Mac. External changes are checked every two seconds and when you return to the app, and conflicting edits pause saving and keep recovery copies."
                )
                SettingsNote(
                    "Local tasks and settings stay on this Mac, in the app data folder above. Apple Reminders and Calendar use their Apple accounts. Chat history stays in memory."
                )
            }
        }
    }

    private var vaultURL: URL? {
        if case .available(let url) = vaultSession.state { return url }
        return nil
    }

    private var vaultDescription: String {
        switch vaultSession.state {
        case .notConfigured: return "None selected"
        case .available(let url): return url.path
        case .needsReauthorization: return "Access needs to be granted again"
        case .unavailable(let why): return why
        }
    }
}

/// Where today's note lives: Obsidian's own daily-note settings (read, never changed) or a custom folder and
/// file name, and the path that resolves to today.
private struct DailyNoteSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var vaultSession: VaultSession
    @FocusState private var focus: Field?

    private enum Field { case folder, filename }

    var body: some View {
        SettingsGroup("Daily note") {
            SettingsRow("Location", description: "Where the app finds and creates today's note.") {
                Picker("Location", selection: $preferences.dailyNoteSource) {
                    Text("Obsidian settings (recommended)").tag(DailyNoteSource.obsidian)
                    Text("Custom").tag(DailyNoteSource.custom)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            switch preferences.dailyNoteSource {
            case .obsidian: obsidianDetails
            case .custom: customFields
            }
            PathSettingsRow("Today's note", path: todayNote.text, monospaced: todayNote.isPath, divider: false)
            SettingsNote(dailyNoteCaption)
        }
    }

    @ViewBuilder private var obsidianDetails: some View {
        switch model.obsidianDailyNotes {
        case .success(let settings?)?:
            Tray {
                Facts([
                    Fact("Folder", settings.folder.isEmpty ? "Vault root" : settings.folder, monospaced: true),
                    Fact("Format", settings.format, monospaced: true),
                    Fact("Template", settings.templatePath ?? "None", monospaced: settings.templatePath != nil),
                ])
            }
            .padding(.vertical, Space.s3)
        case .success(nil)?:
            SettingsNote(
                "This vault has no .obsidian/daily-notes.json, so the Custom folder and file name are used. A note is created in the vault root only if you choose Custom with an empty folder."
            )
            .padding(.bottom, Space.s3)
        case .failure(let error)?:
            ReasonNote(error.localizedDescription, tone: .danger).padding(.vertical, Space.s3)
        case nil:
            SettingsNote("Choose a vault to read its Obsidian daily-note settings.").padding(.bottom, Space.s3)
        }
    }

    private var customFields: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            LabeledField("Folder") {
                TextField("", text: $preferences.dailyFolder, prompt: Text("vault root"))
                    .focused($focus, equals: .folder)
                    .fieldChrome(focused: focus == .folder, monospaced: true)
            }
            LabeledField("File name") {
                TextField("", text: $preferences.dailyFilename, prompt: Text("YYYY-MM-DD"))
                    .focused($focus, equals: .filename)
                    .fieldChrome(focused: focus == .filename, monospaced: true)
            }
        }
        .padding(.vertical, Space.s4)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// Today's vault-relative path, or why it cannot be resolved.
    private var todayNote: (text: String, isPath: Bool) {
        do {
            if vaultSession.vault == nil && preferences.dailyNoteSource == .custom {
                return (try preferences.dailyNoteTemplate.relativePath(for: Date()), true)
            }
            return (try model.resolveDailyNote(for: Date()).path, true)
        } catch {
            return (error.localizedDescription, false)
        }
    }

    private var dailyNoteCaption: String {
        switch preferences.dailyNoteSource {
        case .obsidian:
            return
                "Read from the vault's Obsidian Daily notes settings, which are never changed. New notes start from the template. Existing files are never renamed or moved."
        case .custom:
            return
                "The folder is used as written. File name tokens (Moment format, as in Obsidian): \(MomentFormat.supportedTokens.joined(separator: " ")). Wrap other letters in [brackets]; use / for subfolders. Folders are created on demand. Existing files are never renamed or moved."
        }
    }
}
