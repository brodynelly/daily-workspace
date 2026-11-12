import Combine
import DailyCore
import Foundation

/// Builds the read-only vault readers for one vault root. Injected so tests can hold a read in flight.
typealias OpenLoopSourceFactory = @Sendable (URL) -> [any OpenLoopSource]

/// Open loops from every owner, in one read-only list.
///
/// Org, Seeds and Plot are read from the vault's files off the main actor. Local tasks and reminders are reflected
/// from `TaskStore` and `RemindersService`, which keep their own actions; this store re-derives whenever either
/// publishes. Nothing here ever writes to a source. A key missing from `observations` means that source has not
/// been read yet (before the first refresh of a vault, or Reminders allowed but not loaded); every other condition,
/// including "no vault chosen", is a `SourceState`.
@MainActor
final class OpenLoopsStore: ObservableObject {
    /// The sources this store reflects, in the order the UI lists them. Luuna is not an open-loop source yet.
    static let authorities: [LoopAuthority] = [.local, .org, .seeds, .plot, .reminders]
    /// The sources whose files live in the vault.
    static let vaultAuthorities: [LoopAuthority] = [.org, .seeds, .plot]

    nonisolated static let liveSources: OpenLoopSourceFactory = { root in
        [OrgReader(root: root), SeedsReader(root: root), PlotReader(root: root)]
    }

    /// The latest observation of each source, with its real state.
    @Published private(set) var observations: [LoopAuthority: SourceObservation<[OpenLoop]>] = [:]
    /// Every loop from every observation (including stale values kept across a failed read): not-done first, then
    /// by date (undated last), then title.
    @Published private(set) var loops: [OpenLoop] = []
    @Published private(set) var isRefreshing = false
    /// The vault the file sources are read from.
    @Published private(set) var vaultRoot: URL?

    /// Bumped by every refresh and every vault change. A file read started under an older value is discarded.
    private(set) var generation = 0

    private let tasks: TaskStore
    private let reminders: RemindersService
    private let makeSources: OpenLoopSourceFactory
    private let now: () -> Date
    private let calendar: Calendar
    private var subscriptions: Set<AnyCancellable> = []

    init(
        tasks: TaskStore, reminders: RemindersService, vaultRoot: URL? = nil,
        makeSources: @escaping OpenLoopSourceFactory = OpenLoopsStore.liveSources,
        calendar: Calendar = .current, now: @escaping () -> Date = Date.init
    ) {
        self.tasks = tasks
        self.reminders = reminders
        self.vaultRoot = vaultRoot
        self.makeSources = makeSources
        self.calendar = calendar
        self.now = now
        // `@Published` emits before the property changes, so each sink uses the emitted values.
        tasks.$tasks.combineLatest(tasks.$loadError)
            .sink { [weak self] list, loadError in self?.reflectTasks(list, loadError: loadError) }
            .store(in: &subscriptions)
        reminders.$status.combineLatest(reminders.$items, reminders.$hasLoaded)
            .sink { [weak self] status, items, hasLoaded in
                self?.reflectReminders(status: status, items: items, hasLoaded: hasLoaded)
            }
            .store(in: &subscriptions)
    }

    // MARK: Vault and refresh

    /// Read another vault (or none). Observations of the old vault's files are dropped, and any read still in
    /// flight for it is discarded. Call `refresh()` afterwards.
    func setVaultRoot(_ root: URL?) {
        guard root?.standardizedFileURL != vaultRoot?.standardizedFileURL else { return }
        vaultRoot = root
        generation += 1
        isRefreshing = false
        for authority in Self.vaultAuthorities { observations[authority] = nil }
        rebuild()
    }

    /// Re-reads Org, Seeds and Plot off the main actor and refreshes Reminders (a read; it never asks for access).
    /// Only the newest refresh for the current vault publishes; a failed read keeps the previous value as stale.
    func refresh() async {
        generation += 1
        let generation = generation
        isRefreshing = true
        let root = vaultRoot
        let makeSources = makeSources
        let date = now()
        let files = Task.detached(priority: .userInitiated) { () -> [LoopAuthority: SourceObservation<[OpenLoop]>] in
            guard let root else { return [:] }
            var read: [LoopAuthority: SourceObservation<[OpenLoop]>] = [:]
            for source in makeSources(root) { read[source.authority] = source.readLoops(now: date) }
            return read
        }
        reminders.updateStatus()
        if reminders.status == .authorized { await reminders.refresh() }
        let read = await files.value
        guard generation == self.generation else {
            Log.app.info("Discarded open loops read for an earlier vault or refresh")
            return
        }
        defer { isRefreshing = false }
        guard root != nil else {
            for authority in Self.vaultAuthorities {
                observations[authority] = SourceObservation(
                    state: .unavailable(reason: "No vault is chosen."), value: [], observedAt: date)
            }
            rebuild()
            return
        }
        for (authority, observation) in read {
            observations[authority] = observation.following(observations[authority])
        }
        rebuild()
    }

    // MARK: Queries

    /// Loops from one source (or all), for one project slug (or all). Done items only when asked.
    func loops(authority: LoopAuthority? = nil, project: String? = nil, includeDone: Bool = false) -> [OpenLoop] {
        loops.filter { loop in
            (authority.map { loop.authority == $0 } ?? true) && (project.map { loop.project == $0 } ?? true)
                && (includeDone || !loop.isDoneInSource)
        }
    }

    /// Items whose own date is `day`: Org headings scheduled or due that day (active timestamps), local tasks due
    /// that day and reminders due that day. Never Seeds or Plot, which have no dates of their own to schedule by
    /// (SYSTEM-INVENTORY §3), and never an undated item.
    func dueOn(_ day: LocalDay, includeDone: Bool = false) -> [OpenLoop] {
        loops.filter { loop in
            Self.datedAuthorities.contains(loop.authority) && (includeDone || !loop.isDoneInSource)
                && Self.ownDays(of: loop).contains(day)
        }
    }

    /// Not-done items whose own date is before `day` and that have no date on or after it: overdue Org deadlines
    /// and schedules, local tasks and reminders. Same sources as `dueOn(_:)`.
    func overdue(before day: LocalDay) -> [OpenLoop] {
        loops.filter { loop in
            let days = Self.ownDays(of: loop)
            return Self.datedAuthorities.contains(loop.authority) && !loop.isDoneInSource && !days.isEmpty
                && days.allSatisfy { $0 < day }
        }
    }

    /// Today's stat tiles.
    var counts: OpenLoopCounts { counts(on: LocalDay(now(), calendar: calendar)) }

    func counts(on day: LocalDay) -> OpenLoopCounts {
        let open = loops.filter { !$0.isDoneInSource }
        return OpenLoopCounts(
            open: open.count, dueToday: dueOn(day).count, overdue: overdue(before: day).count,
            bySource: Dictionary(grouping: open, by: \.authority).mapValues(\.count))
    }

    /// The local task behind a `.local` loop, for `TaskStore` actions.
    func task(for loop: OpenLoop) -> TaskItem? {
        guard case .localTask(let id) = loop.sourceLink else { return nil }
        return tasks.tasks.items.first { $0.id == id }
    }

    /// The reminder behind a `.reminders` loop, for `RemindersService` actions.
    func reminder(for loop: OpenLoop) -> ReminderEntry? {
        guard case .reminder(let id) = loop.sourceLink else { return nil }
        return reminders.items.first { $0.id == id }
    }

    // MARK: Reflection of the app's own stores

    static let localOpenStatus = "open"
    static let localDoneStatus = "completed"
    /// `RemindersService` lists incomplete reminders only.
    static let reminderOpenStatus = "incomplete"

    private static let datedAuthorities: Set<LoopAuthority> = [.org, .local, .reminders]

    private func reflectTasks(_ list: TaskList, loadError: String?) {
        let date = now()
        if let loadError {
            observations[.local] = SourceObservation(
                state: .unavailable(reason: loadError), value: [], observedAt: date
            ).following(observations[.local])
        } else {
            let loops = list.items.map { Self.loop(for: $0, observedAt: date) }
            observations[.local] = SourceObservation(
                state: .readable(count: loops.count, issues: []), value: loops, observedAt: date)
        }
        rebuild()
    }

    private func reflectReminders(status: PermissionStatus, items: [ReminderEntry], hasLoaded: Bool) {
        let date = now()
        let state: SourceState
        switch status {
        case .authorized:
            guard hasLoaded else {
                observations[.reminders] = nil
                rebuild()
                return
            }
            state = .readable(count: items.count, issues: [])
        case .notRequested, .denied, .restricted:
            state = .unauthorized
        case .unavailable:
            state = .unavailable(reason: "Reminders is unavailable.")
        }
        let loops = state.isReadable ? items.map { Self.loop(for: $0, observedAt: date, calendar: calendar) } : []
        observations[.reminders] = SourceObservation(state: state, value: loops, observedAt: date)
            .following(observations[.reminders])
        rebuild()
    }

    static func loop(for task: TaskItem, observedAt: Date) -> OpenLoop {
        let due = task.due.map { LoopDate(year: $0.year, month: $0.month, day: $0.day, raw: $0.description) }
        return OpenLoop(
            authority: .local, nativeID: task.id.uuidString, title: task.title, kind: "task",
            nativeStatus: task.isCompleted ? localDoneStatus : localOpenStatus, isDoneInSource: task.isCompleted,
            deadline: due, sourcePath: task.noteLink, revision: ISO8601DateFormatter().string(from: task.updated),
            observedAt: observedAt)
    }

    static func loop(for reminder: ReminderEntry, observedAt: Date, calendar: Calendar = .current) -> OpenLoop {
        let due = reminder.due.map { LoopDate(instant: $0, raw: dueText($0, calendar: calendar), calendar: calendar) }
        return OpenLoop(
            authority: .reminders, nativeID: reminder.id, title: reminder.title, kind: "reminder",
            nativeStatus: reminderOpenStatus, isDoneInSource: false, deadline: due, labels: [reminder.list],
            observedAt: observedAt)
    }

    /// `2026-11-12`, or `2026-11-12 09:30` when the reminder has a time.
    private static func dueText(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        guard let hour = c.hour, let minute = c.minute, hour != 0 || minute != 0 else { return day }
        return day + String(format: " %02d:%02d", hour, minute)
    }

    // MARK: Ordering

    private func rebuild() {
        let all = Self.authorities.flatMap { observations[$0]?.value ?? [] }
        loops = all.sorted(by: Self.precedes)
    }

    /// The days of the item's own active SCHEDULED and DEADLINE (local and reminder due dates are deadlines).
    static func ownDays(of loop: OpenLoop) -> [LocalDay] {
        [loop.scheduled, loop.deadline].compactMap { $0 }.filter(\.isActive).map(\.localDay)
    }

    /// Not-done first, then the earliest own date (undated last), then title, then id.
    static func precedes(_ lhs: OpenLoop, _ rhs: OpenLoop) -> Bool {
        if lhs.isDoneInSource != rhs.isDoneInSource { return !lhs.isDoneInSource }
        switch (sortKey(lhs), sortKey(rhs)) {
        case (let left?, let right?) where left != right: return left.lexicographicallyPrecedes(right)
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        switch lhs.title.localizedStandardCompare(rhs.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }

    /// Year, month, day, then the time of day in minutes (`-1` for an all-day date, so it leads its day).
    private static func sortKey(_ loop: OpenLoop) -> [Int]? {
        [loop.scheduled, loop.deadline].compactMap { $0 }
            .map { date in [date.year, date.month, date.day, date.hour.map { $0 * 60 + (date.minute ?? 0) } ?? -1] }
            .min { $0.lexicographicallyPrecedes($1) }
    }
}

/// Counts for Today's stat tiles. Done items are never counted.
struct OpenLoopCounts: Equatable {
    var open: Int
    var dueToday: Int
    var overdue: Int
    /// Open (not done) loops per source; a source with none is absent.
    var bySource: [LoopAuthority: Int]

    func count(_ authority: LoopAuthority) -> Int { bySource[authority] ?? 0 }
}
