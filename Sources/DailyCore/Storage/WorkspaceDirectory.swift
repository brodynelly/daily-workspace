import Foundation

/// Where Daily Workspace keeps its own files: `~/.config/daily-workspace/`.
///
/// Always under the home folder rather than `$XDG_CONFIG_HOME`: an app opened from the Dock does not see
/// shell variables, so honoring it would split state between launch methods.
public struct WorkspaceDirectory: Equatable {
    public static let folderName = "daily-workspace"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> WorkspaceDirectory {
        WorkspaceDirectory(
            url: home.appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true))
    }

    public var settingsURL: URL { url.appendingPathComponent("settings.json") }
    public var tasksURL: URL { url.appendingPathComponent("tasks.json") }
    /// Discarded sides of note conflicts. Holds note text, so the folder is private to this user.
    public var recoveryFolder: URL { url.appendingPathComponent("recovery", isDirectory: true) }

    /// Create the folder, readable only by this user, if it does not exist yet. An existing folder is left as is.
    public func prepare() throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// Where earlier versions kept tasks and recovery copies.
    public static func legacyFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/DailyWorkspace", isDirectory: true)
    }

    /// Copy `legacyFile` to `destination` when only the legacy file exists. The original stays where it is
    /// and an existing destination is never overwritten. Returns true when a copy was made.
    @discardableResult
    public static func adopt(legacyFile: URL, as destination: URL) throws -> Bool {
        let files = FileManager.default
        guard files.fileExists(atPath: legacyFile.path), !files.fileExists(atPath: destination.path) else {
            return false
        }
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: legacyFile, to: destination)
        return true
    }
}
