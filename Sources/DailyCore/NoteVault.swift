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
        var h: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
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

    public init(root: URL) {
        self.root = root
    }

    /// Resolve a vault-relative path, rejecting anything that escapes the vault.
    public func resolve(relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        let prefix = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(prefix) else { throw VaultError.outsideVault }
        return url
    }

    public func relativePath(of url: URL) -> String? {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
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
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .withoutOverwriting)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw VaultError.alreadyExists
        } catch {
            throw VaultError.io(error.localizedDescription)
        }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return LoadedNote(text: initialText, snapshot: FileSnapshot(data: data, modified: modified))
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

/// Maps a date to the vault-relative path of its daily note. Tokens: YYYY, MM, DD.
public struct DailyNoteTemplate: Equatable {
    public var folder: String
    public var filename: String

    public init(folder: String = "", filename: String = "YYYY-MM-DD") {
        self.folder = folder
        self.filename = filename
    }

    public func relativePath(for date: Date, calendar: Calendar = .current) throws -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { throw VaultError.invalidTemplate("date") }

        func render(_ s: String) -> String {
            s.replacingOccurrences(of: "YYYY", with: String(format: "%04d", y))
                .replacingOccurrences(of: "MM", with: String(format: "%02d", m))
                .replacingOccurrences(of: "DD", with: String(format: "%02d", d))
        }

        var name = render(filename).trimmingCharacters(in: .whitespaces)
        let parts = folder.split(separator: "/").map { render(String($0)).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        guard !name.isEmpty else { throw VaultError.invalidTemplate("empty file name") }
        for part in parts + [name] {
            if part == "." || part == ".." || part.contains("/") || part.contains("\\") || part.contains("\0") {
                throw VaultError.invalidTemplate("path segments not allowed")
            }
        }
        if !name.lowercased().hasSuffix(".md") { name += ".md" }
        return (parts + [name]).joined(separator: "/")
    }
}
