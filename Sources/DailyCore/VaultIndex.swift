import Foundation

public struct IndexedNote: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let text: String
    public var title: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
}

/// A bounded, read-only snapshot. Hidden folders and symlinks are never traversed.
public enum VaultIndex {
    public static func scan(root: URL) throws -> [IndexedNote] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let vault = NoteVault(root: root)
        var notes: [IndexedNote] = []
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md",
                  (values.fileSize ?? 0) <= 2_000_000, let path = vault.relativePath(of: url),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            notes.append(IndexedNote(path: path, text: text))
        }
        return notes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public static func search(_ query: String, in notes: [IndexedNote]) -> [IndexedNote] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return notes.filter { note in terms.allSatisfy { note.path.localizedCaseInsensitiveContains($0) || note.text.localizedCaseInsensitiveContains($0) } }
    }

    public static func backlinks(to path: String, in notes: [IndexedNote]) -> [IndexedNote] {
        let target = (path as NSString).deletingPathExtension.lowercased()
        let basename = (target as NSString).lastPathComponent
        let pattern = #"\[\[([^\]]+)\]\]|\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return notes.filter { note in
            guard note.path != path else { return false }
            let text = note.text as NSString
            return regex.matches(in: note.text, range: NSRange(location: 0, length: text.length)).contains { match in
                let wiki = match.range(at: 1).location != NSNotFound
                let raw = text.substring(with: match.range(at: wiki ? 1 : 2))
                let link = raw.components(separatedBy: "|")[0].components(separatedBy: "#")[0].removingPercentEncoding ?? raw
                let normalized = (link as NSString).deletingPathExtension.lowercased()
                if wiki { return normalized == target || normalized == basename }
                let resolved = URL(fileURLWithPath: "/" + note.path).deletingLastPathComponent().appendingPathComponent(link).standardizedFileURL.path
                return (resolved as NSString).deletingPathExtension.lowercased() == "/" + target
            }
        }
    }
}
