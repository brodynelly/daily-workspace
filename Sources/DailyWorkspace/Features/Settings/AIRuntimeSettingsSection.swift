import DailyCore
import SwiftUI

/// Settings → AI → Runtime: the Assistant's loop limits and offered tools, saved as `assistantRuntime` in
/// `settings.json`. Every value is clamped by `AssistantRuntimeSettings`; only read-only tools exist to offer.
struct AIRuntimeSettingsSection: View {
    @EnvironmentObject private var preferences: Preferences

    private var runtime: AssistantRuntimeSettings { preferences.assistantRuntime }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(
                "Runtime",
                description: "How hard the Assistant works on each question. Changes apply to the next question."
            )
            .padding(.top, Space.s6)
            .padding(.bottom, Space.s1)
            SettingsRow(
                "Lookup rounds per question",
                description: "After the last round the Assistant answers from what it has and says what it missed."
            ) {
                Stepper(
                    value: $preferences.assistantRuntime.maxToolRounds, in: AssistantRuntimeSettings.toolRoundRange
                ) {
                    value("\(runtime.maxToolRounds)")
                }
            }
            SettingsRow("Chat effort", description: "More effort thinks longer and costs more tokens.") {
                effortPicker("Chat effort", selection: $preferences.assistantRuntime.chatEffort)
            }
            SettingsRow("Restart draft effort", description: "Used when drafting a restart record.") {
                effortPicker("Restart draft effort", selection: $preferences.assistantRuntime.draftEffort)
            }
            SettingsRow(
                "Automatic retries",
                description: "Retries after a rate limit, overload or dropped connection, before anything streams."
            ) {
                Stepper(value: $preferences.assistantRuntime.maxRetries, in: AssistantRuntimeSettings.retryRange) {
                    value("\(runtime.maxRetries)")
                }
            }
            SettingsRow(
                "Lookup time limit",
                description: "A slower lookup is reported to the Assistant as unknown, never as empty."
            ) {
                Stepper(
                    value: $preferences.assistantRuntime.toolTimeoutSeconds,
                    in: AssistantRuntimeSettings.toolTimeoutRange, step: 5
                ) {
                    value("\(Int(runtime.toolTimeoutSeconds)) s")
                }
            }
            SettingsRow(
                "Lookups offered",
                description: "All are read-only. Turning one off starts a new conversation.",
                stacked: true,
                divider: false
            ) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(AssistantTool.readOnly, id: \.self) { tool in
                        Toggle(isOn: isOffered(tool)) {
                            Text(tool.rawValue).font(TextRole.mono.font)
                        }
                        .toggleStyle(.checkbox)
                    }
                    Button("Restore defaults") { preferences.assistantRuntime = AssistantRuntimeSettings() }
                        .buttonStyle(.secondary)
                        .disabled(runtime == AssistantRuntimeSettings())
                }
            }
        }
    }

    private func value(_ text: String) -> some View {
        Text(text).font(TextRole.mono.font).foregroundStyle(Theme.ink)
    }

    private func effortPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(AssistantRuntimeSettings.efforts, id: \.self) { effort in
                Text(effort).tag(effort)
            }
        }
        .labelsHidden()
        .frame(width: 160)
    }

    private func isOffered(_ tool: AssistantTool) -> Binding<Bool> {
        Binding(
            get: { !preferences.assistantRuntime.disabledTools.contains(tool.rawValue) },
            set: { offered in
                var names = Set(preferences.assistantRuntime.disabledTools)
                if offered {
                    names.remove(tool.rawValue)
                } else {
                    names.insert(tool.rawValue)
                }
                preferences.assistantRuntime.disabledTools = names.sorted()
            })
    }
}
