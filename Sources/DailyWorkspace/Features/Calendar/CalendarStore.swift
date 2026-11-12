import EventKit
import SwiftUI

struct AgendaEvent: Identifiable, Equatable {
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

/// A calendar the user may add events to.
struct CalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
}

/// A new event (`identifier == nil`) or an edit of one occurrence.
struct EventDraft: Equatable {
    var identifier: String?
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    var location: String
}

struct CalendarError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Calendar data access. `EventKitCalendarStore` is the production implementation.
@MainActor
protocol CalendarStore: AnyObject {
    var authorization: PermissionStatus { get }
    /// Called when the underlying store reports any change.
    var onChange: (() -> Void)? { get set }
    func requestAccess() async throws
    func writableCalendars() -> [CalendarChoice]
    /// Events overlapping `start..<end`, all-day first, then by start time.
    func events(from start: Date, to end: Date) -> [AgendaEvent]
    func save(_ draft: EventDraft) throws
    func deleteEvent(identifier: String) throws
}

@MainActor
final class EventKitCalendarStore: CalendarStore {
    var onChange: (() -> Void)?
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            // The notification only says "something changed": callers refetch rather than patch.
            Task { @MainActor in self?.onChange?() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var authorization: PermissionStatus { PermissionStatus(EKEventStore.authorizationStatus(for: .event)) }

    func requestAccess() async throws {
        _ = try await store.requestFullAccessToEvents()
    }

    func writableCalendars() -> [CalendarChoice] {
        store.calendars(for: .event).filter(\.allowsContentModifications).map {
            CalendarChoice(id: $0.calendarIdentifier, title: $0.title)
        }
    }

    func events(from start: Date, to end: Date) -> [AgendaEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .map(Self.agendaEvent)
    }

    func save(_ draft: EventDraft) throws {
        guard let calendar = store.calendar(withIdentifier: draft.calendarID), calendar.allowsContentModifications
        else {
            throw CalendarError(message: "Select a writable calendar.")
        }
        let event: EKEvent
        if let identifier = draft.identifier {
            guard let existing = store.event(withIdentifier: identifier) else {
                throw CalendarError(message: "The event no longer exists. Refresh the agenda.")
            }
            event = existing
        } else {
            event = EKEvent(eventStore: store)
        }
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.calendar = calendar
        event.location = draft.location.isEmpty ? nil : draft.location
        try store.save(event, span: .thisEvent, commit: true)
    }

    func deleteEvent(identifier: String) throws {
        guard let event = store.event(withIdentifier: identifier), event.calendar.allowsContentModifications else {
            return
        }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private static func agendaEvent(_ event: EKEvent) -> AgendaEvent {
        AgendaEvent(
            identifier: event.eventIdentifier,
            id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
            title: (event.title?.isEmpty == false ? event.title : nil) ?? "Untitled event",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            color: Color(cgColor: event.calendar.cgColor),
            location: (event.location?.isEmpty == false) ? event.location : nil
        )
    }
}
