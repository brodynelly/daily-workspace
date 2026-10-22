import SwiftUI
import AppKit
import DailyCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            vaultTab.tabItem { Label("Vault", systemImage: "folder") }
            motionTab.tabItem { Label("Typing", systemImage: "cursorarrow.motionlines") }
            calendarTab.tabItem { Label("Calendar", systemImage: "calendar") }
        }
        .frame(width: 520, height: 380)
        .padding(20)
    }

    private var vaultTab: some View {
        Form {
            LabeledContent("Vault") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(vaultDescription).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    Button("Choose Vault…") { state.chooseVault() }
                }
            }
            TextField("Daily note folder", text: $state.dailyFolder, prompt: Text("vault root"))
            TextField("File name", text: $state.dailyFilename, prompt: Text("YYYY-MM-DD"))
            LabeledContent("Today's note") {
                Text(previewPath).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Tokens: YYYY, MM, DD. The folder is created on demand. Existing files are never renamed or moved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var motionTab: some View {
        Form {
            Picker("Caret", selection: $state.caretPreset) {
                ForEach(CaretPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            Text(state.caretPreset.detail).font(.caption).foregroundStyle(.secondary)
            if state.systemReduceMotion {
                Label("Reduce Motion is on in macOS, so the native caret is used. Turn it off in System Settings › Accessibility › Display to see animation.", systemImage: "figure.walk.motion")
                    .font(.caption)
            }
            Text("The animated caret switches back to the system caret while you compose text with an input method and while text is selected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var calendarTab: some View {
        Form {
            LabeledContent("Status") { Text(statusText) }
            switch state.calendarService.status {
            case .notRequested:
                Button("Enable Calendar…") { Task { await state.calendarService.requestAccess() } }
            case .denied, .restricted:
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            default:
                EmptyView()
            }
            Text("Events are read-only. The app never creates, edits or deletes calendar events and never asks for Reminders access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var vaultDescription: String {
        switch state.vaultState {
        case .notConfigured: return "None selected"
        case .available(let url): return url.path
        case .needsReauthorization: return "Access needs to be granted again"
        case .unavailable(let why): return why
        }
    }

    private var previewPath: String {
        (try? DailyNoteTemplate(folder: state.dailyFolder, filename: state.dailyFilename).relativePath(for: Date())) ?? "Invalid template"
    }

    private var statusText: String {
        switch state.calendarService.status {
        case .notRequested: return "Not enabled"
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .unavailable: return "Unavailable"
        }
    }
}
