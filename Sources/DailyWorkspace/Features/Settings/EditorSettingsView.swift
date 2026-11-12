import DailyCore
import SwiftUI

struct EditorSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Picker("Caret", selection: $preferences.caretPreset) {
                ForEach(CaretPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            Text(preferences.caretPreset.detail).font(.caption).foregroundStyle(.secondary)
            if model.systemReduceMotion {
                Label(
                    "Reduce Motion is on in macOS, so the native caret is used. Turn it off in System Settings → Accessibility → Display to see animation.",
                    systemImage: "figure.walk.motion"
                )
                .font(.caption)
            }
            Text(
                "The animated caret switches back to the system caret while you compose text with an input method and while text is selected."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
