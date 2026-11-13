import DailyCore
import Foundation

/// Which owner the Open Loops list shows.
enum LoopSourceFilter: String, CaseIterable, Hashable, Sendable {
    case all, local, reminders, luuna, mail

    /// The owner this filter keeps, or nil for every owner.
    var authority: LoopAuthority? {
        switch self {
        case .all: return nil
        case .local: return .local
        case .reminders: return .reminders
        case .luuna: return .luuna
        case .mail: return .mail
        }
    }

    var title: String { authority?.ownerName ?? "All" }
}

/// The Open Loops list's filters: one source (or all), one project slug (or all), and whether finished items show.
struct OpenLoopsFilter: Equatable, Sendable {
    var source: LoopSourceFilter = .all
    /// A project slug as the owner states it; nil for every project.
    var project: String?
    var showDone = false

    /// `loops` in their given order, keeping only those that pass every filter.
    func apply(to loops: [OpenLoop]) -> [OpenLoop] {
        loops.filter { loop in
            (source.authority.map { loop.authority == $0 } ?? true)
                && (project.map { loop.project == $0 } ?? true)
                && (showDone || !loop.isDoneInSource)
        }
    }

    /// The project slugs the owners state on `loops`, sorted, each once.
    static func projects(in loops: [OpenLoop]) -> [String] {
        Set(loops.compactMap(\.project)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// What a row may do. Writes go only to the app's own stores; Mail and Luuna have no actions here.
enum LoopAction: Hashable, Sendable {
    case complete
    case reopen
    case edit
    case delete
    case completeReminder

}

extension OpenLoop {
    /// The actions its owner accepts from this app.
    var ownerActions: [LoopAction] {
        switch authority {
        case .local:
            return [isDoneInSource ? .reopen : .complete, .edit, .delete]
        case .reminders:
            return isDoneInSource ? [] : [.completeReminder]
        case .luuna, .mail:
            return []
        }
    }

    /// The owner's dates, as supplied by that source.
    var dateLines: [String] {
        guard authority != .mail else { return [] }
        return [
            scheduled.map { "Scheduled \($0.raw)" },
            deadline.map { "Due \($0.raw)" },
            closed.map { "Closed \($0.raw)" },
        ].compactMap { $0 }
    }

}

extension LoopAuthority {
    /// The owner's name as the source tag shows it.
    var ownerName: String {
        switch self {
        case .local: return "Local"
        case .reminders: return "Reminders"
        case .luuna: return "Luuna"
        case .mail: return "Mail"
        }
    }
}
