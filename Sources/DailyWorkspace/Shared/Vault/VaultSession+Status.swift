import Foundation

extension VaultSession.State {
    /// The sidebar footer's status line: a tone and one phrase. Only a live, accessible vault is green.
    var statusTone: Tone {
        switch self {
        case .available: return .success
        case .needsReauthorization: return .attention
        case .unavailable: return .danger
        case .notConfigured: return .neutral
        }
    }

    var statusLabel: String {
        switch self {
        case .available: return "Vault connected"
        case .needsReauthorization: return "Vault access needed"
        case .unavailable: return "Vault unavailable"
        case .notConfigured: return "No vault selected"
        }
    }

    /// The tooltip: the vault's folder, or why it cannot be used.
    var statusDetail: String {
        switch self {
        case .available(let url): return url.path
        case .needsReauthorization: return "Choose the vault folder again to restore access."
        case .unavailable(let why): return why
        case .notConfigured: return "Choose your Obsidian vault folder to use notes."
        }
    }
}
