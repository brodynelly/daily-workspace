import SwiftUI

/// Settings window: Vault, Editor, AI, Permissions.
struct SettingsView: View {
    var body: some View {
        TabView {
            VaultSettingsView().tabItem { Label("Vault", systemImage: "folder") }
            EditorSettingsView().tabItem { Label("Editor", systemImage: "cursorarrow.motionlines") }
            AISettingsView().tabItem { Label("AI", systemImage: "bubble.left") }
            PermissionsSettingsView().tabItem { Label("Permissions", systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 460)
        .padding(20)
    }
}
