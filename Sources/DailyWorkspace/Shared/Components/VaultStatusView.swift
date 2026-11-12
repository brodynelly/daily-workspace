import SwiftUI

/// The one place that explains a missing or unusable vault and offers "Choose Vault…".
struct VaultStatusView: View {
    enum Style { case inline, fullScreen }

    @EnvironmentObject private var model: AppModel
    let state: VaultSession.State
    var style: Style = .fullScreen

    var body: some View {
        switch style {
        case .inline:
            VStack(alignment: .leading, spacing: 8) {
                Text(copy.description).foregroundStyle(.secondary)
                chooseButton
            }
        case .fullScreen:
            ContentUnavailableView {
                Label(copy.title, systemImage: copy.symbol)
            } description: {
                Text(copy.description)
            } actions: {
                chooseButton
            }
        }
    }

    private var chooseButton: some View {
        Button(AppCommand.chooseVault.title) { model.chooseVault() }
    }

    private struct Copy {
        let title: String
        let symbol: String
        let description: String
    }

    private var copy: Copy {
        switch state {
        case .notConfigured, .available:
            return Copy(
                title: "No vault selected", symbol: "folder.badge.questionmark",
                description: "Choose the folder of your Obsidian vault. Notes stay plain Markdown files there.")
        case .needsReauthorization:
            return Copy(
                title: "Vault access needed", symbol: "lock",
                description:
                    "macOS no longer lets the app open the vault. Choose the folder again to restore access.")
        case .unavailable(let why):
            return Copy(title: "Vault unavailable", symbol: "exclamationmark.triangle", description: why)
        }
    }
}
