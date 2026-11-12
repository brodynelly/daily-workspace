import AppKit
import DailyCore

/// Turns the remembered security-scoped bookmark into an accessible `NoteVault`.
@MainActor
final class VaultSession: ObservableObject {
    enum State: Equatable {
        case notConfigured
        case available(URL)
        case needsReauthorization
        case unavailable(String)
    }

    @Published private(set) var state: State = .notConfigured
    private(set) var vault: NoteVault?

    private let preferences: Preferences
    private var accessedURL: URL?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Ask the user for a vault folder. Returns nil when cancelled.
    static func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Vault"
        panel.message = "Choose the folder that holds your Obsidian vault."
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Remember `url` as the vault and open it.
    func adopt(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            preferences.rememberVault(at: url, bookmark: bookmark)
        } catch {
            Log.vault.error(
                "Bookmark creation failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            stopAccessing()
            state = .unavailable("The folder could not be remembered: \(error.localizedDescription)")
            return
        }
        resolve()
    }

    /// Re-open the remembered vault, refreshing a stale bookmark when possible.
    func resolve() {
        stopAccessing()
        guard let data = preferences.vaultBookmark else {
            state = .notConfigured
            return
        }
        var stale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            Log.vault.error(
                "Bookmark resolution failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            state = .needsReauthorization
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            Log.vault.error("Security-scoped access refused for \(url.path, privacy: .private)")
            state = .needsReauthorization
            return
        }
        accessedURL = url
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            Log.vault.notice("Vault folder missing at \(url.path, privacy: .private)")
            state = .unavailable("The vault folder is missing or has moved. Choose it again.")
            return
        }
        if stale {
            do {
                let bookmark = try url.bookmarkData(
                    options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                preferences.rememberVault(at: url, bookmark: bookmark)
                Log.vault.info("Refreshed stale vault bookmark")
            } catch {
                // The old bookmark still resolved, so keep using it; it is retried on the next launch.
                Log.vault.error(
                    "Stale bookmark refresh failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
                )
            }
        }
        preferences.noteVaultLocation(url)
        vault = NoteVault(root: url)
        state = .available(url)
    }

    private func stopAccessing() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        vault = nil
    }
}
