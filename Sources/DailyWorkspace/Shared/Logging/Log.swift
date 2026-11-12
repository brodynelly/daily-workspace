import Foundation
import OSLog

/// Unified-log channels. Stream them with `scripts/build_and_run.sh --app-logs`.
/// Never log note text, chat content or credentials; mark paths `.private`. Error descriptions can embed
/// file names, so log them via `Log.code(_:)` (public) plus a `.private(mask: .hash)` description.
enum Log {
    static let subsystem = "app.dailyworkspace.mac"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let vault = Logger(subsystem: subsystem, category: "vault")
    static let notes = Logger(subsystem: subsystem, category: "notes")
    static let tasks = Logger(subsystem: subsystem, category: "tasks")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let reminders = Logger(subsystem: subsystem, category: "reminders")
    static let chat = Logger(subsystem: subsystem, category: "chat")

    /// Stable, path-free identity of an error, e.g. "NSCocoaErrorDomain#260".
    static func code(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain)#\(ns.code)"
    }
}
