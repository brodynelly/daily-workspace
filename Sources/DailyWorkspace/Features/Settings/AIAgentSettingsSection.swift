import AppKit
import DailyCore
import SwiftUI

/// Settings → AI → Agent: what the durable Assistant keeps and may change. Saved as `agent` in `settings.json`.
/// Luuna and Org stay read-only whatever is chosen here.
struct AIAgentSettingsSection: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var model: AppModel
    @State private var folders = ""
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(
                "Agent",
                description: "What the Assistant remembers, runs on its own and may change in the vault. Changing "
                    + "what it may change starts a new conversation."
            )
            .padding(.top, Space.s6)
            .padding(.bottom, Space.s1)
            vaultRows
            historyRows
            SettingsRow(
                "Memory",
                description: "Short notes the Assistant keeps across conversations, in the app's folder, not the vault."
            ) {
                HStack {
                    Button("Show files") { NSWorkspace.shared.open(model.agentMemory.root) }
                        .buttonStyle(.secondary)
                        .disabled(!FileManager.default.fileExists(atPath: model.agentMemory.root.path))
                    Toggle("Memory", isOn: $preferences.agent.memory).labelsHidden()
                }
            }
            AgentRoutinesSettings(scheduler: model.routines)
        }
        .onAppear { folders = preferences.agent.autoApplyFolders.joined(separator: ", ") }
    }

    @ViewBuilder private var vaultRows: some View {
        SettingsRow("Vault writes", description: "Let the Assistant create notes, append to them and edit them.") {
            Toggle("Vault writes", isOn: $preferences.agent.vaultWrites).labelsHidden()
        }
        SettingsRow(
            "Approval",
            description: "Every change is journaled and can be reviewed in Assistant → Changes. Edits to "
                + "existing text and changes that add links or embeds always wait for review."
        ) {
            Picker("Approval", selection: $preferences.agent.writeApproval) {
                Text("Review every change").tag(AgentSettings.WriteApproval.review)
                Text("Auto-apply in chosen folders").tag(AgentSettings.WriteApproval.autoApplyFolders)
                Text("Auto-apply new notes and appends everywhere").tag(AgentSettings.WriteApproval.autoApplyAll)
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!preferences.agent.vaultWrites)
        }
        SettingsRow(
            "Auto-apply folders",
            description: "Vault-relative folders, comma-separated. New notes and appends here apply at once."
        ) {
            TextField("00-inbox", text: $folders)
                .frame(width: 260)
                .onSubmit(saveFolders)
                .disabled(preferences.agent.writeApproval != .autoApplyFolders || !preferences.agent.vaultWrites)
        }
        SettingsRow("Automatic changes per run", description: "Later changes in the same run wait for review.") {
            Stepper(value: $preferences.agent.maxAutoWritesPerRun, in: AgentSettings.autoWriteRange) {
                Text("\(preferences.agent.maxAutoWritesPerRun)").font(TextRole.mono.font)
            }
        }
    }

    @ViewBuilder private var historyRows: some View {
        SettingsRow(
            "Save conversations",
            description: "Chats are encrypted on this Mac with a key in your Keychain and reopen from the AI page."
        ) {
            Toggle("Save conversations", isOn: $preferences.agent.saveConversations).labelsHidden()
        }
        SettingsRow("Keep conversations for", description: "Older chats are deleted when the app starts.") {
            Stepper(
                value: $preferences.agent.conversationRetentionDays, in: AgentSettings.retentionRange, step: 30
            ) {
                Text("\(preferences.agent.conversationRetentionDays) days").font(TextRole.mono.font)
            }
        }
        SettingsRow(
            "Chat history",
            description: "\(model.conversationArchive.conversations.count) saved"
                + (model.conversationArchive.unreadable > 0
                    ? ", \(model.conversationArchive.unreadable) unreadable" : "")
        ) {
            Button("Delete all history", role: .destructive) { confirmingDelete = true }
                .buttonStyle(.secondary)
                .confirmationDialog("Delete every saved conversation?", isPresented: $confirmingDelete) {
                    Button("Delete all", role: .destructive) { model.conversationArchive.deleteAll() }
                }
        }
    }

    private func saveFolders() {
        preferences.agent.autoApplyFolders = folders.split(separator: ",").map(String.init)
        folders = preferences.agent.autoApplyFolders.joined(separator: ", ")
    }
}

/// Routines: questions the Assistant asks itself on a schedule while the app is open. Each run is saved as a
/// conversation, and its vault changes follow the approval setting (its edits always wait for review).
struct AgentRoutinesSettings: View {
    @ObservedObject var scheduler: RoutineScheduler
    @EnvironmentObject private var preferences: Preferences
    @State private var name = ""
    @State private var prompt = ""
    @State private var schedule = RoutineSchedule()

    var body: some View {
        SettingsRow(
            "Routines",
            description: "Run only while the app is open and the Assistant is on; a run missed while the Mac slept "
                + "happens once when it wakes.",
            stacked: true,
            divider: false
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Toggle("Run routines", isOn: $preferences.agent.routines)
                if let error = scheduler.storageError { ReasonNote(error, tone: .danger) }
                ForEach(scheduler.routines) { routine in row(routine) }
                editor
            }
            .frame(width: 560, alignment: .leading)
        }
    }

    private func row(_ routine: AgentRoutine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Toggle(
                "",
                isOn: Binding(
                    get: { routine.enabled },
                    set: { enabled in
                        var updated = routine
                        updated.enabled = enabled
                        scheduler.update(updated)
                    })
            )
            .labelsHidden()
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(verbatim: routine.name).textRole(.bodyStrong, lineBox: false)
                Text(verbatim: Self.status(routine)).textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Button(scheduler.running == routine.id ? "Running…" : "Run now") { scheduler.run(routine.id) }
                .buttonStyle(.secondary)
                .disabled(scheduler.running != nil)
            Button("Delete", role: .destructive) { scheduler.delete(routine.id) }.buttonStyle(.text)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            BoxedTextField("Name, e.g. Morning brief", text: $name)
            TextArea("What the routine asks", text: $prompt, prompt: "What should the routine ask?", height: 96)
            HStack {
                Picker("Schedule", selection: $schedule.kind) {
                    Text("Daily").tag(RoutineSchedule.Kind.daily)
                    Text("Weekdays").tag(RoutineSchedule.Kind.weekdays)
                    Text("Weekly").tag(RoutineSchedule.Kind.weekly)
                    Text("Every few hours").tag(RoutineSchedule.Kind.interval)
                }
                .fixedSize()
                if schedule.kind == .interval {
                    Stepper(value: $schedule.intervalHours, in: RoutineSchedule.intervalRange) {
                        Text("every \(schedule.intervalHours) h").font(TextRole.mono.font)
                    }
                } else {
                    Stepper(value: $schedule.hour, in: 0...23) {
                        Text(String(format: "%02d:%02d", schedule.hour, schedule.minute)).font(TextRole.mono.font)
                    }
                }
                Spacer()
                Button("Add routine") {
                    scheduler.add(name: name, prompt: prompt, schedule: schedule)
                    name = ""
                    prompt = ""
                }
                .buttonStyle(.primary)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    static func status(_ routine: AgentRoutine) -> String {
        var parts = [routine.schedule.summary]
        if let last = routine.lastRunAt {
            parts.append("last run \(last.formatted(date: .abbreviated, time: .shortened))")
        }
        if let outcome = routine.lastOutcome, outcome != "answered" { parts.append(outcome) }
        if routine.enabled, let next = routine.nextRun() {
            parts.append("next \(next.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }
}
