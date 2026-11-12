import DailyCore
import SwiftUI

struct EditorSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        SettingsPage {
            SettingsGroup("Caret") {
                SettingsRow("Style", description: preferences.caretPreset.detail, divider: false) {
                    Picker("Caret", selection: $preferences.caretPreset) {
                        ForEach(CaretPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                if model.systemReduceMotion {
                    Callout(
                        "Reduce Motion is on in macOS, so the native caret is used. Turn it off in System Settings → Accessibility → Display to see animation."
                    )
                    .padding(.bottom, Space.s1)
                }
                SettingsNote(
                    "The animated caret switches back to the system caret while you compose text with an input method and while text is selected."
                )
            }
        }
    }
}
