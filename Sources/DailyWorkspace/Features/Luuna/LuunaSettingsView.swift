import DailyCore
import SwiftUI

/// Settings › Luuna: the runtime origin and bearer token. Connect validates the origin (HTTP loopback only) before
/// anything is saved or sent, keeps the token in the Keychain, and reconnects. The status line is green only for a
/// live, authenticated connection.
struct LuunaSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var luuna: LuunaStore
    @State private var origin = ""
    @State private var token = ""
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ObservedSourceLine(status: LuunaStatusWords.connection(luuna))
                    Text("Only loopback runtimes are accepted. The token is stored in the macOS Keychain.")
                        .textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notice = model.luunaSettingsNotice { Callout(notice, tone: .attention) }
                }
                .padding(.bottom, Space.s2)
                SettingsRow("Runtime URL", description: "The address of a Luuna runtime already running on this Mac.") {
                    BoxedTextField(LuunaOrigin.standard.description, text: $origin, monospaced: true, onSubmit: connect)
                        .frame(width: 240)
                }
                SettingsRow(
                    "Token",
                    description: luuna.hasToken ? "A token is saved. Leave empty to keep it." : "No token is saved."
                ) {
                    BoxedTextField("Bearer token", text: $token, secure: true, onSubmit: connect).frame(width: 240)
                }
                HStack(spacing: Space.s2) {
                    Button("Connect", action: connect).buttonStyle(.primary)
                    Button("Remove token", action: removeToken)
                        .buttonStyle(.secondary)
                        .disabled(!luuna.hasToken)
                }
                .padding(.top, Space.s4)
                if let message { ReasonNote(message, tone: .danger).padding(.top, Space.s3) }
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { origin = luuna.origin.description }
    }

    private func connect() {
        message = Self.connect(model, origin: origin, token: token)
        if message == nil { token = "" }
    }

    private func removeToken() {
        message = model.connectLuuna(origin: luuna.origin.description, token: "")
    }

    /// Validates and saves through `AppModel.connectLuuna`. An empty token field keeps the saved token. Returns why
    /// it was refused; a non-loopback origin is refused before anything is saved.
    static func connect(_ model: AppModel, origin: String, token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.connectLuuna(origin: origin, token: trimmed.isEmpty ? nil : trimmed)
    }
}
