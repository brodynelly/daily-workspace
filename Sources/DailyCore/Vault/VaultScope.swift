import Foundation

/// Why a path was left out of a traversal.
public enum VaultExclusion: String, CaseIterable, Hashable, Sendable {
    case hidden
    case underscored
    case archive
    case templates
    case automation
    case rawIngest
    case nestedRepository
    case symlink
    case generatedBoard
}

/// The exclusion policy (SYSTEM-INVENTORY §8.5). It is decided from paths and directory listings alone,
/// so excluded content is never read.
public struct VaultScope: Hashable, Sendable {
    /// Vault-relative folder prefixes, each with the class it reports as.
    public var excludedFolders: [String: VaultExclusion]
    /// File-name suffixes of generated or historical boards.
    public var boardSuffixes: [String]

    public init(excludedFolders: [String: VaultExclusion], boardSuffixes: [String]) {
        self.excludedFolders = excludedFolders
        self.boardSuffixes = boardSuffixes
    }

    public static let standard = VaultScope(
        excludedFolders: [
            "04-archive": .archive,
            "templates": .templates,
            "00-inbox/automation": .automation,
            "00-inbox/.ingest": .rawIngest,
            "00-inbox/remarkable": .rawIngest,
            "00-inbox/kb-intake": .rawIngest,
        ],
        boardSuffixes: ["-board.md", "-kanban.md"])

    /// The rule that excludes `path` (vault-relative), checked component by component, or nil when it is in
    /// scope. Nested repositories and symlinks need the file system; `traverse` checks those.
    public func exclusion(forPath path: String, isDirectory: Bool) -> VaultExclusion? {
        let components = path.split(separator: "/").map(String.init)
        let normalized = components.joined(separator: "/")
        let folders = excludedFolders.keys.sorted()
        if let folder = folders.first(where: { normalized == $0 || normalized.hasPrefix($0 + "/") }) {
            return excludedFolders[folder]
        }
        if components.contains(where: { $0.hasPrefix(".") }) { return .hidden }
        if components.contains(where: { $0.hasPrefix("_") }) { return .underscored }
        guard !isDirectory, let name = components.last?.lowercased() else { return nil }
        return boardSuffixes.contains { name.hasSuffix($0) } ? .generatedBoard : nil
    }

    /// Lists the in-scope files under `subpath` (vault-relative, empty for the whole vault). Excluded folders
    /// are not entered. `maxDepth` limits how many path components below `subpath` a file may have
    /// (`1` = files directly inside it). Never reads file content.
    public func traverse(
        root: URL, subpath: String = "", maxDepth: Int? = nil, extensions: Set<String> = ["md"]
    ) -> VaultTraversal {
        var walk = Walk(scope: self, root: root.standardizedFileURL, extensions: extensions, maxDepth: maxDepth)
        let trimmed = subpath.split(separator: "/").joined(separator: "/")
        if !trimmed.isEmpty, let exclusion = exclusion(forPath: trimmed, isDirectory: true) {
            walk.skipped[exclusion, default: 0] += 1
        } else {
            walk.visit(trimmed, depth: 0)
        }
        return VaultTraversal(
            files: walk.files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            skipped: walk.skipped, unreadablePaths: walk.unreadable)
    }
}

/// One in-scope file found by a traversal.
public struct VaultFile: Hashable, Sendable {
    /// Vault-relative path.
    public let path: String
    public let url: URL
    public let size: Int?
    public let modified: Date?
}

/// What a traversal found, and what it left out.
public struct VaultTraversal: Hashable, Sendable {
    public let files: [VaultFile]
    /// Entries skipped by policy. An excluded folder counts once; its contents are not listed.
    public let skipped: [VaultExclusion: Int]
    /// Vault-relative paths that could not be listed or read.
    public let unreadablePaths: [String]

    public init(files: [VaultFile], skipped: [VaultExclusion: Int], unreadablePaths: [String]) {
        self.files = files
        self.skipped = skipped
        self.unreadablePaths = unreadablePaths
    }

    public var skippedUnreadable: Int { unreadablePaths.count }
    /// False when part of the vault could not be listed or read, so results may be missing items.
    public var isComplete: Bool { unreadablePaths.isEmpty }

    public func skipped(_ exclusion: VaultExclusion) -> Int { skipped[exclusion] ?? 0 }
}

/// Depth-first walk that applies the scope before descending or listing a file.
private struct Walk {
    let scope: VaultScope
    let root: URL
    let extensions: Set<String>
    let maxDepth: Int?
    var files: [VaultFile] = []
    var skipped: [VaultExclusion: Int] = [:]
    var unreadable: [String] = []

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
    ]

    mutating func visit(_ relative: String, depth: Int) {
        let folder = relative.isEmpty ? root : root.appendingPathComponent(relative)
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Self.keys, options: [])
        } catch {
            unreadable.append(relative.isEmpty ? "." : relative)
            return
        }
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let path = relative.isEmpty ? entry.lastPathComponent : relative + "/" + entry.lastPathComponent
            visitEntry(entry, path: path, depth: depth + 1)
        }
    }

    private mutating func visitEntry(_ entry: URL, path: String, depth: Int) {
        guard let values = try? entry.resourceValues(forKeys: Set(Self.keys)) else {
            unreadable.append(path)
            return
        }
        let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
        if let exclusion = scope.exclusion(forPath: path, isDirectory: isDirectory) {
            skipped[exclusion, default: 0] += 1
        } else if values.isSymbolicLink == true {
            skipped[.symlink, default: 0] += 1
        } else if isDirectory {
            visitFolder(entry, path: path, depth: depth)
        } else if values.isRegularFile == true, extensions.contains(entry.pathExtension.lowercased()),
            maxDepth.map({ depth <= $0 }) ?? true
        {
            files.append(
                VaultFile(path: path, url: entry, size: values.fileSize, modified: values.contentModificationDate))
        }
    }

    private mutating func visitFolder(_ folder: URL, path: String, depth: Int) {
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) {
            skipped[.nestedRepository, default: 0] += 1
            return
        }
        if let maxDepth, depth >= maxDepth { return }
        visit(path, depth: depth)
    }
}
