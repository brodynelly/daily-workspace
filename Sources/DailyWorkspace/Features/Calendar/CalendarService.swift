import Foundation

/// The agenda of one selected day plus explicit, user-initiated event edits.
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var status: PermissionStatus = .notRequested
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var weekEvents: [AgendaEvent] = []
    @Published private(set) var lastRefreshed: Date?
    /// The day the agenda shows. Owned here so reactivation and day changes reload this day, not "now".
    @Published private(set) var selectedDay = Date()

    private let store: CalendarStore
    private var observesWeek = false

    init(store: CalendarStore) {
        self.store = store
        updateStatus()
        store.onChange = { [weak self] in self?.reload() }
    }

    var writableCalendars: [CalendarChoice] { store.writableCalendars() }

    /// A week fetch is needed only while the Calendar screen is on display.
    func startWeekObservation() {
        observesWeek = true
    }

    func stopWeekObservation() {
        observesWeek = false
        weekEvents = []
    }

    func updateStatus() {
        status = store.authorization
    }

    /// Call only after explaining why access is wanted, in response to the user's action.
    func requestAccess() async {
        do {
            try await store.requestAccess()
        } catch {
            Log.calendar.error(
                "Calendar access request failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            status = .unavailable
            return
        }
        reload()
    }

    func save(_ draft: EventDraft) throws {
        guard status == .authorized, draft.end > draft.start, !draft.calendarID.isEmpty else {
            throw CalendarError(message: "Select a writable calendar and an end time after the start.")
        }
        do {
            try store.save(draft)
        } catch {
            Log.calendar.error(
                "Event save failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            throw error
        }
        reload()
    }

    func deleteEvent(identifier: String) throws {
        do {
            try store.deleteEvent(identifier: identifier)
        } catch {
            Log.calendar.error(
                "Event delete failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            throw error
        }
        reload()
    }

    /// Show another day and fetch its events.
    func show(day: Date) {
        selectedDay = day
        reload()
    }

    /// Refetch the selected day, e.g. after the store changed or the app became active.
    func reload() {
        updateStatus()
        guard status == .authorized else {
            events = []
            weekEvents = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDay)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        events = store.events(from: start, to: end)
        if observesWeek, let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) {
            weekEvents = store.events(from: week.start, to: week.end)
        }
        lastRefreshed = Date()
    }

    /// Read-only panel snapshot. This deliberately does not change the Calendar screen's selected day.
    /// EventKit queries are bounded to today and, if needed, the following seven days.
    func todayAgenda(at now: Date = Date(), calendar: Calendar = .current) -> QuickPanelCalendarSnapshot {
        let permission = store.authorization
        guard permission == .authorized else { return .access(permission) }

        let start = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else {
            return .access(.unavailable)
        }
        let today = store.events(from: start, to: tomorrow)
        if let next = Self.nextEvent(in: today, after: now) {
            return .agenda(events: today, next: next)
        }

        guard let horizon = calendar.date(byAdding: .day, value: 7, to: tomorrow) else {
            return .agenda(events: today, next: nil)
        }
        let later = store.events(from: tomorrow, to: horizon)
        return .agenda(events: today, next: Self.nextEvent(in: later, after: now))
    }

    private static func nextEvent(in events: [AgendaEvent], after now: Date) -> AgendaEvent? {
        var next: AgendaEvent?
        for event in events where event.end > now {
            guard let current = next else {
                next = event
                continue
            }
            let eventStart = max(event.start, now)
            let currentStart = max(current.start, now)
            if eventStart < currentStart
                || (eventStart == currentStart && event.isAllDay != current.isAllDay && !event.isAllDay)
                || (eventStart == currentStart && event.isAllDay == current.isAllDay && event.start < current.start)
            {
                next = event
            }
        }
        return next
    }
}
