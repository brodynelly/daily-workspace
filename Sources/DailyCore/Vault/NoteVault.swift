import Foundation

public enum VaultError: Error, Equatable, LocalizedError {
    case notUTF8
    case missing
    case conflict
    case alreadyExists
    case outsideVault
    case invalidTemplate(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .notUTF8: return "This file is not valid UTF-8, so it was left untouched."
        case .missing: return "The note no longer exists on disk."
        case .conflict: return "The note changed outside the app."
        case .alreadyExists: return "A note with that name already exists."
        case .outsideVault: return "That path is outside the selected vault."
        case .invalidTemplate(let why): return "The daily-note template is invalid (\(why))."
        case .io(let message): return message
        }
    }
}

/// Cheap identity of a file's content. Modification time is recorded but not compared,
/// so a sync tool touching the file without changing it is not a conflict.
public struct FileSnapshot: Equatable {
    public let fingerprint: UInt64
    public let size: Int
    public let modified: Date?

    public static func == (lhs: FileSnapshot, rhs: FileSnapshot) -> Bool {
        lhs.fingerprint == rhs.fingerprint && lhs.size == rhs.size
    }

    public init(data: Data, modified: Date?) {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325  // FNV-1a
        for byte in data {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        fingerprint = h
        size = data.count
        self.modified = modified
    }
}

public struct LoadedNote {
    public let text: String
    public let snapshot: FileSnapshot
}

/// Reads and writes Markdown inside one user-selected folder. Never deletes, renames or reorganises files,
/// never rewrites a file it did not load, and refuses to overwrite content that changed on disk.
public struct NoteVault {
    public let root: URL

    /// `root` is canonicalized once (symlinks resolved), so every child URL is built from the real folder.
    public init(root: URL) {
        self.root = root.resolvingSymlinksInPath().standardized
    }

    /// Resolve a vault-relative path, rejecting anything that escapes the vault.
    ///
    /// Normalization is lexical (`standardized`, not `standardizedFileURL`): the file-system variant strips
    /// `/private` only from paths that exist, so a new note under `/private/tmp` would look outside its vault.
    /// A symlink inside the vault that leads outside it (or nowhere) is rejected as well.
    public func resolve(relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath).standardized
        guard let inside = Self.path(url.path, under: root.path) else { throw VaultError.outsideVault }
        var current = root
        for component in inside.split(separator: "/") {
            current.appendPathComponent(String(component))
            guard (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true else { continue }
            let target = current.resolvingSymlinksInPath().standardized
            guard target != current, Self.path(target.path, under: root.path) != nil else {
                throw VaultError.outsideVault
            }
        }
        return url
    }

    /// Vault-relative path of `url`, or nil when it lies outside the vault. URLs built from `root` match
    /// lexically; URLs from the file system (enumerators, panels) may spell the root through a symlink such
    /// as `/private/var`, so those are compared in symlink-resolved form.
    public func relativePath(of url: URL) -> String? {
        if let path = Self.path(url.standardized.path, under: root.standardized.path) { return path }
        return Self.path(url.resolvingSymlinksInPath().path, under: root.resolvingSymlinksInPath().path)
    }

    private static func path(_ path: String, under base: String) -> String? {
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func currentSnapshot(of url: URL) throws -> FileSnapshot? {
        guard exists(url) else { return nil }
        let data = try Data(contentsOf: url)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return FileSnapshot(data: data, modified: modified)
    }

    public func load(_ url: URL) throws -> LoadedNote {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw VaultError.io(error.localizedDescription) }
        guard let text = String(data: data, encoding: .utf8) else { throw VaultError.notUTF8 }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return LoadedNote(text: text, snapshot: FileSnapshot(data: data, modified: modified))
    }

    /// Create a new note. Fails rather than replacing an existing file.
    public func create(_ url: URL, initialText: String) throws -> LoadedNote {
        _ = try resolve(relativePath: relativePath(of: url) ?? "")
        let data = Data(initialText.utf8)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .withoutOverwriting)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw VaultError.alreadyExists
        } catch {
            throw VaultError.io(error.localizedDescription)
        }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return LoadedNote(text: initialText, snapshot: FileSnapshot(data: data, modified: modified))
    }

    /// Append one block of text to a note on disk, creating it with `initialText` first when missing.
    /// Uses the same snapshot check as `save`, so a concurrent external edit is reported, never overwritten.
    @discardableResult
    public func append(_ block: String, to url: URL, creatingWith initialText: String) throws -> LoadedNote {
        let loaded = exists(url) ? try load(url) : try create(url, initialText: initialText)
        let text = NoteVault.appending(block, to: loaded.text)
        let snapshot = try save(text, to: url, expecting: loaded.snapshot)
        return LoadedNote(text: text, snapshot: snapshot)
    }

    /// `body` followed by `block` on its own line.
    public static func appending(_ block: String, to body: String) -> String {
        var result = body
        if !result.isEmpty && !result.hasSuffix("\n") { result += "\n" }
        return result + block
    }

    /// Atomic save that only proceeds if the file on disk still matches what was loaded.
    public func save(_ text: String, to url: URL, expecting expected: FileSnapshot) throws -> FileSnapshot {
        guard let current = try currentSnapshot(of: url) else { throw VaultError.missing }
        guard current == expected else { throw VaultError.conflict }
        let data = Data(text.utf8)
        do { try data.write(to: url, options: .atomic) } catch { throw VaultError.io(error.localizedDescription) }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return FileSnapshot(data: data, modified: modified)
    }
}
