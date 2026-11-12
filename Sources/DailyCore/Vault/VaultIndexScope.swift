import Foundation

/// An index built under the exclusion policy, with what was left out.
public struct ScopedVaultIndex: Sendable {
    public let notes: [IndexedNote]
    public let traversal: VaultTraversal
    /// Listed files that could not be read as UTF-8 text.
    public let unreadableNotes: [String]
    /// Listed files over the size limit, which were not read.
    public let oversizedNotes: [String]

    /// Folders and files that could not be listed or read. Non-zero means the index may be missing notes.
    public var skippedUnreadable: Int { traversal.skippedUnreadable + unreadableNotes.count }
    public var isComplete: Bool { skippedUnreadable == 0 }
}

extension VaultIndex {
    /// Like `scan(root:)`, but applies `scope` before reading any content and reports what it skipped.
    /// Opt-in: `scan(root:)` keeps its behaviour.
    public static func scan(root: URL, scope: VaultScope, maxFileSize: Int = 2_000_000) -> ScopedVaultIndex {
        let traversal = scope.traverse(root: root)
        var notes: [IndexedNote] = []
        var unreadable: [String] = []
        var oversized: [String] = []
        for file in traversal.files {
            if let size = file.size, size > maxFileSize {
                oversized.append(file.path)
            } else if let data = try? Data(contentsOf: file.url), let text = String(data: data, encoding: .utf8) {
                notes.append(IndexedNote(path: file.path, text: text))
            } else {
                unreadable.append(file.path)
            }
        }
        return ScopedVaultIndex(
            notes: notes, traversal: traversal, unreadableNotes: unreadable, oversizedNotes: oversized)
    }
}
