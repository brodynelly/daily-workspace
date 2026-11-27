import DailyCore
import Foundation

/// Where the Assistant may read in the vault: a vault-relative path that `NoteVault.resolve` accepts, that the
/// exclusion policy (SYSTEM-INVENTORY §8.5) leaves in scope, with no symbolic link and no nested repository on
/// the way. Decided from paths and the file system's metadata alone, so refused content is never read.
enum VaultReadPolicy {
    /// A path the policy allows: its URL and its normalized vault-relative path.
    struct Allowed: Equatable, Sendable {
        let url: URL
        let path: String
    }

    /// File types the Assistant reads as notes.
    static let noteExtensions: Set<String> = ["md"]

    /// Resolve `raw` inside the vault at `root`, or throw a `ToolFailure` that says why it is refused. The
    /// message names the path, never its content.
    static func resolve(_ raw: String, root: URL, scope: VaultScope) throws -> Allowed {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw ToolFailure("Give a vault-relative path.") }
        guard !path.hasPrefix("/"), !path.hasPrefix("~") else {
            throw ToolFailure("\(path) is outside the vault, so it was not read. Use a vault-relative path.")
        }
        let vault = NoteVault(root: root)
        let url: URL
        do {
            url = try vault.resolve(relativePath: path)
        } catch {
            throw ToolFailure("\(path) is outside the vault, so it was not read.")
        }
        guard let relative = vault.relativePath(of: url) else {
            throw ToolFailure("\(path) is outside the vault, so it was not read.")
        }
        if let exclusion = scope.exclusion(forPath: relative, isDirectory: false)
            ?? fileSystemExclusion(relative, root: vault.root)
        {
            throw ToolFailure(
                "\(relative) is excluded from what the Assistant may read (\(describe(exclusion))). It was not read.")
        }
        return Allowed(url: url, path: relative)
    }

    /// A symbolic link anywhere on the path, or a folder on the way that holds its own repository.
    static func fileSystemExclusion(_ relative: String, root: URL) -> VaultExclusion? {
        let files = FileManager.default
        var current = root
        let components = relative.split(separator: "/").map(String.init)
        for (index, component) in components.enumerated() {
            current.appendPathComponent(component)
            let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true { return .symlink }
            let isFolder = index < components.count - 1
            if isFolder, files.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return .nestedRepository
            }
        }
        return nil
    }

    static func describe(_ exclusion: VaultExclusion) -> String {
        switch exclusion {
        case .hidden: return "a hidden path"
        case .underscored: return "a path starting with _"
        case .archive: return "the archive"
        case .templates: return "templates"
        case .automation: return "generated automation"
        case .rawIngest: return "raw ingest"
        case .nestedRepository: return "a nested repository"
        case .symlink: return "a symbolic link"
        case .generatedBoard: return "a generated board"
        }
    }
}
