import DailyCore
import Foundation

/// The owning app store for a local task or reminder.
enum OpenLoopSourceLink: Hashable, Sendable {
    /// A task in `TaskStore`; look it up with `OpenLoopsStore.task(for:)`.
    case localTask(UUID)
    /// A reminder in `RemindersService`, by calendar item identifier; see `OpenLoopsStore.reminder(for:)`.
    case reminder(String)
}

extension OpenLoop {
    /// The route back to this item's owner, or nil when the owner gave no location.
    var sourceLink: OpenLoopSourceLink? {
        switch authority {
        case .local:
            return UUID(uuidString: String(id.dropFirst(LoopAuthority.local.rawValue.count + 1))).map {
                .localTask($0)
            }
        case .reminders:
            return .reminder(String(id.dropFirst(LoopAuthority.reminders.rawValue.count + 1)))
        case .luuna, .mail:
            return nil
        }
    }
}
