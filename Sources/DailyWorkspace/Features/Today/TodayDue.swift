import DailyCore
import Foundation

/// One row of Today's "Due today": an item whose own date is today, or an overdue one.
struct TodayDueItem: Identifiable, Equatable {
    let loop: OpenLoop
    let isOverdue: Bool

    var id: String { loop.id }
}

/// What Today shows from Open Loops. Pure, so it can be tested without a view.
///
/// Only local tasks and reminders with their own due dates are listed. Luuna and Mail items
/// are never listed: Today does not invent daily attention for them.
@MainActor
enum TodayDue {
    /// The owners whose items may appear in "Due today".
    static let datedAuthorities: Set<LoopAuthority> = [.local, .reminders]

    /// Overdue first (in Open Loops order), then what is due today: open items before done ones.
    static func items(dueToday: [OpenLoop], overdue: [OpenLoop], on day: LocalDay) -> [TodayDueItem] {
        let listable = { (loop: OpenLoop) in
            datedAuthorities.contains(loop.authority) && !OpenLoopsStore.ownDays(of: loop).isEmpty
        }
        let late = overdue.filter(listable).map { TodayDueItem(loop: $0, isOverdue: true) }
        let lateIDs = Set(late.map(\.id))
        let current = dueToday.filter { listable($0) && !lateIDs.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.isDoneInSource != rhs.isDoneInSource ? !lhs.isDoneInSource : OpenLoopsStore.precedes(lhs, rhs)
            }
            .map { TodayDueItem(loop: $0, isOverdue: false) }
        return late + current
    }

    /// The rows for `day` from the store: done items due today stay listed (after the open ones).
    static func items(from store: OpenLoopsStore, on day: LocalDay) -> [TodayDueItem] {
        items(dueToday: store.dueOn(day, includeDone: true), overdue: store.overdue(before: day), on: day)
    }

    /// The badge tone follows the owner's native status, without inferring a new status.
    static func tone(for loop: OpenLoop) -> Tone {
        LoopTone.tone(for: loop)
    }

    /// The owner's name, for the source tag.
    static func sourceName(_ authority: LoopAuthority) -> String { authority.ownerName }

    /// "Scheduled 09:30" for an item due today with a time, "Deadline Nov 10" for an overdue one, nil for an item
    /// due today without a time.
    static func when(_ item: TodayDueItem, on day: LocalDay, calendar: Calendar = .current) -> String? {
        let loop = item.loop
        let dated: [(label: String, date: LoopDate)] = [
            loop.scheduled.map { ("Scheduled", $0) },
            loop.deadline.map { ("Due", $0) },
        ].compactMap { $0 }.filter { $0.date.isActive }
        if item.isOverdue {
            guard let latest = dated.filter({ $0.date.localDay < day }).max(by: { $0.date.localDay < $1.date.localDay })
            else { return nil }
            let date = latest.date.localDay.date(in: calendar) ?? Date()
            let dayText = date.formatted(.dateTime.month(.abbreviated).day())
            return [latest.label, dayText, time(of: latest.date, calendar: calendar)].compactMap { $0 }
                .joined(separator: " ")
        }
        guard let todays = dated.first(where: { $0.date.localDay == day && $0.date.hour != nil }),
            let time = time(of: todays.date, calendar: calendar)
        else { return nil }
        return "\(todays.label) \(time)"
    }

    private static func time(of date: LoopDate, calendar: Calendar) -> String? {
        guard let hour = date.hour else { return nil }
        let components = DateComponents(
            year: date.year, month: date.month, day: date.day, hour: hour, minute: date.minute ?? 0)
        return calendar.date(from: components)?.formatted(date: .omitted, time: .shortened)
    }

    /// Why an owner of dated items could not be read completely, so "nothing due" never hides an unreadable
    /// source. Reminders that are simply not allowed are a choice, not a failure, and are not reported. Nil while
    /// the source has not been read yet, and when it was read completely.
    static func notice(for authority: LoopAuthority, _ observation: SourceObservation<[OpenLoop]>?) -> String? {
        guard let observation else { return nil }
        let name = authority == .local ? "Local tasks" : sourceName(authority)
        let problem: String
        switch observation.state {
        case .empty, .populated: return nil
        case .unauthorized:
            guard authority != .reminders else { return nil }
            problem = "\(name) could not be read: access was denied."
        case .unsupported: problem = "\(name) cannot be read on this Mac."
        case .unavailable(let reason): problem = "\(name) could not be read: \(sentence(reason))"
        case .refused(let reason): problem = "\(name) was not read: \(sentence(reason))"
        case .uninitialized: problem = "\(name) is not set up in this vault."
        case .partial(let issues):
            let count = issues.count == 1 ? "1 problem" : "\(issues.count) problems"
            return "\(name) was read with \(count). Some of its items may be missing here."
        }
        let stale = observation.lastSuccessAt.map {
            " Showing what was read at \($0.formatted(date: .omitted, time: .shortened))."
        }
        return problem + (stale ?? " Items it holds may be missing here.")
    }

    /// `text` ending in a full stop, so a following sentence reads cleanly.
    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".!?".contains(last) else { return trimmed }
        return trimmed + "."
    }

    /// Every notice for the owners Today lists, in Open Loops order.
    static func notices(from store: OpenLoopsStore) -> [String] {
        OpenLoopsStore.authorities.filter(datedAuthorities.contains).compactMap {
            notice(for: $0, store.observations[$0])
        }
    }
}

/// One stat tile on Today.
struct TodayStat: Identifiable, Equatable {
    let term: String
    let value: String
    var comparison: String?

    var id: String { term }
}

extension TodayDue {
    /// The four tiles: today's event count (only while Calendar is readable; otherwise no number, so an unreadable
    /// calendar never reads as an empty day), then `OpenLoopsStore.counts(on:)` unchanged.
    static func stats(counts: OpenLoopCounts, events: Int?) -> [TodayStat] {
        let eventTile =
            events.map { TodayStat(term: "Events today", value: $0.formatted()) }
            ?? TodayStat(term: "Events today", value: "—", comparison: "Calendar not connected")
        return [
            eventTile,
            TodayStat(term: "Due today", value: counts.dueToday.formatted()),
            TodayStat(term: "Overdue", value: counts.overdue.formatted()),
            TodayStat(term: "Open loops", value: counts.open.formatted()),
        ]
    }
}
