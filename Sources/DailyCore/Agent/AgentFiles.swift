import Foundation

extension WorkspaceDirectory {
    /// The durable Assistant's own files: saved chats, memory, the vault change queue and its audit journal,
    /// and routines. They hold note text and chat, so the folder is readable only by this user.
    public var agentFolder: URL { url.appendingPathComponent("agent", isDirectory: true) }
    /// One encrypted file per saved conversation.
    public var agentConversationsFolder: URL { agentFolder.appendingPathComponent("conversations", isDirectory: true) }
    /// The Assistant's long-term memory: small Markdown files it reads and edits with its `memory` tool.
    public var agentMemoryFolder: URL { agentFolder.appendingPathComponent("memories", isDirectory: true) }
    /// Proposed, applied, rejected and undone vault changes with their before and after text.
    public var vaultChangesURL: URL { agentFolder.appendingPathComponent("vault-changes.json") }
    /// Append-only audit of every vault change event: paths and hashes, never note text.
    public var vaultJournalURL: URL { agentFolder.appendingPathComponent("vault-journal.jsonl") }
    /// Scheduled Assistant runs the user created.
    public var routinesURL: URL { agentFolder.appendingPathComponent("routines.json") }
}

/// Files only this user can read, written so a crash leaves either the old or the new version.
public enum PrivateFile {
    /// Create `folder` and its parents, readable only by this user. An existing folder is left as is.
    public static func prepare(_ folder: URL) throws {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// Atomically replace `url` with `data` (write to a temporary file, then rename), mode 0600.
    public static func write(_ data: Data, to url: URL) throws {
        try prepare(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Append `line` and a newline to `url`, creating it with mode 0600, and flush it to disk.
    public static func appendLine(_ line: Data, to url: URL) throws {
        try prepare(url.deletingLastPathComponent())
        let files = FileManager.default
        if !files.fileExists(atPath: url.path) {
            guard files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line + Data("\n".utf8))
        try handle.synchronize()
    }

    /// The file's bytes, or nil when it does not exist.
    public static func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// An encoder that writes the same bytes for the same value.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
