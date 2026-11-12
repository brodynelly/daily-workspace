import AppKit
import DailyCore
import SwiftUI

struct VaultSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var vaultSession: VaultSession

    var body: some View {
        Form {
            Section("Vault") {
                LabeledContent("Folder") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(vaultDescription).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                        HStack {
                            if case .available(let url) = vaultSession.state {
                                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            }
                            Button(AppCommand.chooseVault.title) { model.chooseVault() }
                        }
                    }
                }
            }
            dailyNoteSection
            Section("App data") {
                LabeledContent("Folder") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(model.directory.url.path).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Show in Finder") { NSWorkspace.shared.open(model.directory.url) }
                    }
                }
                Text(
                    "settings.json, tasks.json and recovery copies of notes live here. Your API key stays in the macOS Keychain."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("Syncing") {
                Text(
                    "To sync, choose a vault inside iCloud Drive, Dropbox, OneDrive, or another synced folder. That service transfers the Markdown files; keep them downloaded on each Mac. External changes are checked every two seconds and when you return to the app, and conflicting edits pause saving and keep recovery copies."
                )
                Text(
                    "Local tasks and settings stay on this Mac, in the app data folder above. Apple Reminders and Calendar use their Apple accounts. Chat history stays in memory."
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var vaultDescription: String {
        switch vaultSession.state {
        case .notConfigured: return "None selected"
        case .available(let url): return url.path
        case .needsReauthorization: return "Access needs to be granted again"
        case .unavailable(let why): return why
        }
    }

    private var dailyNoteSection: some View {
        Section("Daily note") {
            Picker("Location", selection: $preferences.dailyNoteSource) {
                Text("Obsidian settings (recommended)").tag(DailyNoteSource.obsidian)
                Text("Custom").tag(DailyNoteSource.custom)
            }
            switch preferences.dailyNoteSource {
            case .obsidian: obsidianDetails
            case .custom:
                TextField("Folder", text: $preferences.dailyFolder, prompt: Text("vault root"))
                TextField("File name", text: $preferences.dailyFilename, prompt: Text("YYYY-MM-DD"))
            }
            LabeledContent("Today's note") {
                Text(todayNote).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
            Text(dailyNoteCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var obsidianDetails: some View {
        switch model.obsidianDailyNotes {
        case .success(let settings?)?:
            LabeledContent("Folder", value: settings.folder.isEmpty ? "Vault root" : settings.folder)
            LabeledContent("Format", value: settings.format)
            LabeledContent("Template", value: settings.templatePath ?? "None")
        case .success(nil)?:
            Text(
                "This vault has no .obsidian/daily-notes.json, so the Custom folder and file name are used. A note is created in the vault root only if you choose Custom with an empty folder."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .failure(let error)?:
            Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
        case nil:
            Text("Choose a vault to read its Obsidian daily-note settings.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var todayNote: String {
        do {
            if vaultSession.vault == nil && preferences.dailyNoteSource == .custom {
                return try preferences.dailyNoteTemplate.relativePath(for: Date())
            }
            return try model.resolveDailyNote(for: Date()).path
        } catch {
            return error.localizedDescription
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
