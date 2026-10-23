import EventKit
import SwiftUI

struct AgendaEvent: Identifiable {
    let identifier: String
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let color: Color
    let location: String?
}

/// Calendar reads and explicit user-initiated event edits.
@MainActor
final class CalendarService: ObservableObject {
    enum Status: Equatable {
        case notRequested, authorized, denied, restricted, unavailable
    }

    @Published private(set) var status: Status = .notRequested
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var lastRefreshed: Date?

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var shownDay = Date()

    init() {
        updateStatus()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            // The notification only says "something changed": refetch rather than patching.
            Task { @MainActor in self?.refresh(day: self?.shownDay ?? Date()) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func updateStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: status = .notRequested
        case .fullAccess: status = .authorized
        case .denied: status = .denied
        case .restricted: status = .restricted
        case .writeOnly: status = .denied // cannot read events with write-only access
        @unknown default: status = .unavailable
        }
    }

    /// Call only after explaining why access is wanted, in response to the user's action.
    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            status = .unavailable
            return
        }
        updateStatus()
        refresh(day: shownDay)
    }

    struct WritableCalendar: Identifiable {
        let id: String
        let title: String
    }

    var writableCalendars: [WritableCalendar] {
        store.calendars(for: .event).filter(\.allowsContentModifications).map { WritableCalendar(id: $0.calendarIdentifier, title: $0.title) }
    }

    func saveEvent(identifier: String?, title: String, start: Date, end: Date, allDay: Bool, calendarID: String, location: String) throws {
        guard status == .authorized, end > start,
              let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else {
            throw NSError(domain: "DailyWorkspace", code: 1, userInfo: [NSLocalizedDescriptionKey: "Select a writable calendar and an end time after the start."])
        }
        let event: EKEvent
        if let identifier {
            guard let existing = store.event(withIdentifier: identifier) else {
                throw NSError(domain: "DailyWorkspace", code: 2, userInfo: [NSLocalizedDescriptionKey: "The event no longer exists. Refresh the agenda."])
            }
            event = existing
        } else { event = EKEvent(eventStore: store) }
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        event.calendar = calendar
        event.location = location.isEmpty ? nil : location
        try store.save(event, span: .thisEvent, commit: true)
        refresh(day: shownDay)
    }

    func deleteEvent(identifier: String) throws {
        guard let event = store.event(withIdentifier: identifier), event.calendar.allowsContentModifications else { return }
        try store.remove(event, span: .thisEvent, commit: true)
        refresh(day: shownDay)
    }

    func refresh(day: Date) {
        shownDay = day
        updateStatus()
        guard status == .authorized else {
            events = []
            return
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let found = store.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .map { e in
                AgendaEvent(
                    identifier: e.eventIdentifier,
                    id: "\(e.calendarItemIdentifier)-\(e.startDate.timeIntervalSince1970)",
                    title: (e.title?.isEmpty == false ? e.title : nil) ?? "Untitled event",
                    start: e.startDate,
                    end: e.endDate,
                    isAllDay: e.isAllDay,
                    calendarID: e.calendar.calendarIdentifier,
                    calendarTitle: e.calendar.title,
                    color: Color(cgColor: e.calendar.cgColor),
                    location: (e.location?.isEmpty == false) ? e.location : nil
                )
            }
        events = found
        lastRefreshed = Date()
    }
}
