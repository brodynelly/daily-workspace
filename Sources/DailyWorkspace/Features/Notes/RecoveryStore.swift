import Foundation

/// Where the discarded side of a conflict is kept. Outside the vault, so the vault stays untouched.
protocol RecoveryStoring {
    var folder: URL? { get }
    /// Write `text` to the recovery folder. Throws so callers never discard text that was not kept.
    func stash(_ text: String, label: String) throws
}

struct RecoveryStore: RecoveryStoring {
    let folder: URL?

    func stash(_ text: String, label: String) throws {
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = folder.appendingPathComponent("\(stamp)-\(label)-\(UUID().uuidString.prefix(8)).md")
        try Data(text.utf8).write(to: file, options: [.atomic, .withoutOverwriting])
        Log.notes.info("Stashed \(label, privacy: .public) in recovery folder")
    }
}
