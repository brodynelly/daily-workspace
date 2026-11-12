import DailyCore
import Foundation

/// Which owner the Open Loops list shows.
enum LoopSourceFilter: String, CaseIterable, Hashable, Sendable {
    case all, local, org, seeds, plot, reminders

    /// The owner this filter keeps, or nil for every owner.
    var authority: LoopAuthority? {
        switch self {
        case .all: return nil
        case .local: return .local
        case .org: return .org
        case .seeds: return .seeds
        case .plot: return .plot
        case .reminders: return .reminders
        }
    }

    var title: String { authority?.ownerName ?? "All" }
}

/// The Open Loops list's filters: one source (or all), one project slug (or all), and whether finished items show.
struct OpenLoopsFilter: Equatable, Sendable {
    var source: LoopSourceFilter = .all
    /// A project slug as the owner states it (the Seeds `project:<slug>` label); nil for every project.
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

/// What a row may do. Every action goes to the item's owner; only the app's own stores (`tasks.json` through
/// `TaskStore`, Apple Reminders through `RemindersService`) accept writes. Org, Seeds and Plot rows can only be
/// opened at their source.
enum LoopAction: Hashable, Sendable {
    case complete
    case reopen
    case edit
    case delete
    case completeReminder
    case openSource

    /// True when the action changes the owner's data.
    var writes: Bool { self != .openSource }
}

extension OpenLoop {
    /// The actions its owner accepts from this app.
    var ownerActions: [LoopAction] {
        switch authority {
        case .local:
            return [isDoneInSource ? .reopen : .complete, .edit, .delete]
        case .reminders:
            return isDoneInSource ? [] : [.completeReminder]
        case .org, .seeds, .plot:
            return sourceLink == nil ? [] : [.openSource]
        case .luuna:
            return []
        }
    }

    /// The owner's own id, without the `authority:` prefix.
    var ownerID: String { String(id.dropFirst(authority.rawValue.count + 1)) }

    /// A stable generated id worth showing as a `ShortId` (Seeds and Plot ids); nil for Org headings (content
    /// hashes or `:ID:` properties), local tasks and reminders.
    var displayedID: String? {
        switch authority {
        case .seeds, .plot: return ownerID
        case .org, .local, .reminders, .luuna: return nil
        }
    }

    /// The owner's dates, verbatim, with their meaning: `Scheduled …`, `Deadline …` (`Due …` for local tasks and
    /// reminders, whose only date is a due date), `Closed …`.
    var dateLines: [String] {
        let dueWord = authority == .local || authority == .reminders ? "Due" : "Deadline"
        return [
            scheduled.map { "Scheduled \($0.raw)" },
            deadline.map { "\(dueWord) \($0.raw)" },
            closed.map { "Closed \($0.raw)" },
        ]
        .compactMap { $0 }
    }

    /// Where the owner keeps it, as `path:line`, for vault sources.
    var sourceLocation: String? {
        guard let path = sourceLink?.vaultPath else { return nil }
        return line.map { "\(path):\($0)" } ?? path
    }
}

extension LoopAuthority {
    /// The owner's name as the source tag shows it.
    var ownerName: String {
        switch self {
        case .org: return "Org"
        case .seeds: return "Seeds"
        case .plot: return "Plot"
        case .local: return "Local"
        case .reminders: return "Reminders"
        case .luuna: return "Luuna"
        }
    }
}
