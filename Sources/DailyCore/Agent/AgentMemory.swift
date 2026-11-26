import Foundation

/// The Assistant's long-term memory: plain-text files under `/memories`, kept in the app's own folder (never in
/// the vault) and edited only through the commands of Anthropic's memory tool. The user can read, edit and
/// delete every file in Settings → AI → Agent.
///
/// Paths are confined to the folder: no `..`, no hidden or absolute components, no symbolic links. Files and
/// the folder are size-capped so memory cannot grow without bound or crowd the context window.
public struct AgentMemory: Sendable {
    public let root: URL

    public static let maxFileBytes = 16_000
    public static let maxTotalBytes = 256_000
    public static let maxFiles = 200
    /// Allowed file types: Markdown and plain text.
    public static let extensions: Set<String> = ["md", "txt"]

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public struct Failure: Error, Equatable, LocalizedError {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    /// One memory file, for Settings.
    public struct File: Equatable, Sendable, Identifiable {
        /// `/memories/…`
        public let path: String
        public let size: Int
        public let modified: Date?
        public var id: String { path }
    }

    // MARK: Commands

    /// A directory listing (for `/memories` or a subfolder) or a file's lines numbered from 1.
    public func view(_ path: String, range: ClosedRange<Int>? = nil) throws -> String {
        let url = try resolve(path, allowRoot: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            if path == "/memories" || path == "/memories/" { return "Directory: /memories\n(empty)" }
            throw Failure("\(path) does not exist.")
        }
        if isDirectory.boolValue {
            let files = try list().filter { $0.path.hasPrefix(Self.display(url, root: root) + "/") }
            let rows = files.map { "- \($0.path) (\($0.size) bytes)" }
            let listing = rows.isEmpty ? "(empty)" : rows.joined(separator: "\n")
            return "Directory: \(Self.display(url, root: root))\n" + listing
        }
        let lines = try text(at: url).components(separatedBy: "\n")
        let selected = range.map { max(1, $0.lowerBound)...min(lines.count, $0.upperBound) } ?? 1...max(1, lines.count)
        guard selected.lowerBound <= selected.upperBound else { throw Failure("view_range is outside the file.") }
        return selected.map { "\($0)\t\(lines[$0 - 1])" }.joined(separator: "\n")
    }

    public func create(_ path: String, text: String) throws {
        let url = try resolve(path)
        try checkSize(text, replacing: url)
        if !FileManager.default.fileExists(atPath: url.path), try list().count >= Self.maxFiles {
            throw Failure("Memory already holds \(Self.maxFiles) files. Update or delete one first.")
        }
        try PrivateFile.write(Data(text.utf8), to: url)
    }

    public func replace(_ path: String, old: String, new: String) throws {
        let url = try resolve(path)
        let current = try text(at: url)
        guard !old.isEmpty else { throw Failure("old_str must not be empty.") }
        let count = current.components(separatedBy: old).count - 1
        guard count == 1 else {
            throw Failure(
                count == 0
                    ? "old_str was not found in \(path). View the file and copy the text exactly."
                    : "old_str appears \(count) times in \(path). Include more surrounding text so it is unique.")
        }
        let updated = current.replacingOccurrences(of: old, with: new)
        try checkSize(updated, replacing: url)
        try PrivateFile.write(Data(updated.utf8), to: url)
    }

    public func insert(_ path: String, line: Int, text inserted: String) throws {
        let url = try resolve(path)
        var lines = try text(at: url).components(separatedBy: "\n")
        guard (0...lines.count).contains(line) else {
            throw Failure("insert_line must be between 0 and \(lines.count).")
        }
        lines.insert(contentsOf: inserted.components(separatedBy: "\n"), at: line)
        let updated = lines.joined(separator: "\n")
        try checkSize(updated, replacing: url)
        try PrivateFile.write(Data(updated.utf8), to: url)
    }

    /// Delete a memory file (memory is app-owned; vault files are never deleted).
    public func delete(_ path: String) throws {
        let url = try resolve(path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw Failure("\(path) does not exist.") }
        try FileManager.default.removeItem(at: url)
    }

    public func rename(_ path: String, to newPath: String) throws {
        let source = try resolve(path)
        let target = try resolve(newPath)
        let files = FileManager.default
        guard files.fileExists(atPath: source.path) else { throw Failure("\(path) does not exist.") }
        guard !files.fileExists(atPath: target.path) else { throw Failure("\(newPath) already exists.") }
        try PrivateFile.prepare(target.deletingLastPathComponent())
        try files.moveItem(at: source, to: target)
    }

    // MARK: Reading for the prompt and Settings

    /// Every memory file, sorted by path.
    public func list() throws -> [File] {
        let files = FileManager.default
        guard files.fileExists(atPath: root.path) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard
            let walker = files.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var found: [File] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isSymbolicLink != true, values?.isRegularFile == true,
                Self.extensions.contains(url.pathExtension.lowercased())
            else { continue }
            found.append(
                File(
                    path: Self.display(url, root: root), size: values?.fileSize ?? 0,
                    modified: values?.contentModificationDate))
        }
        return found.sorted { $0.path < $1.path }
    }

    /// A file's text, for Settings.
    public func read(_ path: String) throws -> String {
        try text(at: try resolve(path))
    }

    /// The memory index the Assistant sees at the start of each run: file paths and sizes, never contents,
    /// so it decides what to view (Anthropic's memory-tool protocol).
    public func index() -> String {
        guard let files = try? list(), !files.isEmpty else { return "/memories is empty." }
        return files.map { "\($0.path) (\($0.size) bytes)" }.joined(separator: "\n")
    }

    // MARK: Paths

    /// `/memories/a/b.md` → a URL under `root`. Anything that could leave the folder is refused.
    public func resolve(_ path: String, allowRoot: Bool = false) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == "/memories" || trimmed.hasPrefix("/memories/") else {
            throw Failure("Memory paths start with /memories/.")
        }
        let parts = trimmed.split(separator: "/").map(String.init).dropFirst()
        if parts.isEmpty {
            guard allowRoot else { throw Failure("Name a file under /memories/.") }
            return root
        }
        guard !parts.contains(where: { $0 == ".." || $0 == "." || $0.hasPrefix(".") || $0.contains("\\") }) else {
            throw Failure("\(trimmed) is not a valid memory path.")
        }
        var url = root
        for part in parts {
            url.appendPathComponent(part)
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw Failure("\(trimmed) is not a valid memory path.")
            }
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if !(exists && isDirectory.boolValue) || !allowRoot {
            guard Self.extensions.contains(url.pathExtension.lowercased()) else {
                throw Failure("Memory files end in .md or .txt.")
            }
        }
        return url
    }

    private func text(at url: URL) throws -> String {
        guard let data = try PrivateFile.read(url) else {
            throw Failure("\(Self.display(url, root: root)) does not exist.")
        }
        guard let text = String(data: data, encoding: .utf8) else { throw Failure("That memory file is not UTF-8.") }
        return text
    }

    private func checkSize(_ text: String, replacing url: URL) throws {
        let size = text.utf8.count
        guard size <= Self.maxFileBytes else {
            throw Failure("A memory file holds at most \(Self.maxFileBytes) bytes. Keep it shorter or split it.")
        }
        let others = try list().filter { $0.path != Self.display(url, root: root) }.reduce(0) { $0 + $1.size }
        guard others + size <= Self.maxTotalBytes else {
            throw Failure("Memory is full (\(Self.maxTotalBytes) bytes). Condense or delete older files first.")
        }
    }

    private static func display(_ url: URL, root: URL) -> String {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return "/memories" }
        return "/memories" + path.dropFirst(base.count)
    }
}
