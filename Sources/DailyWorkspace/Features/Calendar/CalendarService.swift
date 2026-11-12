import Foundation

/// The agenda of one selected day plus explicit, user-initiated event edits.
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var status: PermissionStatus = .notRequested
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var lastRefreshed: Date?
    /// The day the agenda shows. Owned here so reactivation and day changes reload this day, not "now".
    @Published private(set) var selectedDay = Date()

    private let store: CalendarStore

    init(store: CalendarStore) {
        self.store = store
        updateStatus()
        store.onChange = { [weak self] in self?.reload() }
    }

    var writableCalendars: [CalendarChoice] { store.writableCalendars() }

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
            return
        }
        let start = Calendar.current.startOfDay(for: selectedDay)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        events = store.events(from: start, to: end)
        lastRefreshed = Date()
    }
}
