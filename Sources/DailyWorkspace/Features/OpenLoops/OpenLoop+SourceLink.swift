import DailyCore
import Foundation

/// Where an open loop's owner keeps it, so the UI can route back to that owner. Following a link never writes:
/// vault files are opened in Notes or revealed in Finder, and local tasks and reminders are acted on through
/// `TaskStore` and `RemindersService`.
enum OpenLoopSourceLink: Hashable, Sendable {
    /// A vault-relative text file to open in Notes (Org files), at a 1-based line when known.
    case note(path: String, line: Int?)
    /// A vault-relative file to reveal in Finder (Seeds JSONL, Plot JSON), at a 1-based line when known.
    case vaultFile(path: String, line: Int?)
    /// A task in `TaskStore`; look it up with `OpenLoopsStore.task(for:)`.
    case localTask(UUID)
    /// A reminder in `RemindersService`, by calendar item identifier; see `OpenLoopsStore.reminder(for:)`.
    case reminder(String)

    /// The vault-relative path for a vault file, nil for app-owned items.
    var vaultPath: String? {
        switch self {
        case .note(let path, _), .vaultFile(let path, _): return path
        case .localTask, .reminder: return nil
        }
    }
}

extension OpenLoop {
    /// The route back to this item's owner, or nil when the owner gave no location.
    var sourceLink: OpenLoopSourceLink? {
        switch authority {
        case .org:
            return sourcePath.map { .note(path: $0, line: line) }
        case .seeds, .plot:
            return sourcePath.map { .vaultFile(path: $0, line: line) }
        case .local:
            return UUID(uuidString: String(id.dropFirst(LoopAuthority.local.rawValue.count + 1))).map {
                .localTask($0)
            }
        case .reminders:
            return .reminder(String(id.dropFirst(LoopAuthority.reminders.rawValue.count + 1)))
        case .luuna:
            return nil
        }
    }
}
