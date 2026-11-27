// EventKit predates Sendable annotations; its store is only used from the main actor here.
@preconcurrency import EventKit
import Foundation

struct ReminderEntry: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let list: String
    let due: Date?
}

struct ReminderError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Apple Reminders access. `EventKitReminderStore` is the production implementation.
@MainActor
protocol ReminderStore: AnyObject {
    var authorization: PermissionStatus { get }
    func requestAccess() async throws
    /// Incomplete reminders, soonest due first, undated last.
    func incompleteReminders() async -> [ReminderEntry]
    /// Add to the default list.
    func add(title: String, due: Date?) throws
    func complete(id: String) throws
}

@MainActor
final class EventKitReminderStore: ReminderStore {
    private let store = EKEventStore()

    var authorization: PermissionStatus { PermissionStatus(EKEventStore.authorizationStatus(for: .reminder)) }

    func requestAccess() async throws {
        _ = try await store.requestFullAccessToReminders()
    }

    func incompleteReminders() async -> [ReminderEntry] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        // Convert in EventKit's callback so only Sendable values cross back to the main actor.
        let entries: [ReminderEntry] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(
                    returning: (reminders ?? []).map {
                        ReminderEntry(
                            id: $0.calendarItemIdentifier, title: $0.title ?? "Untitled reminder",
                            list: $0.calendar.title, due: $0.dueDateComponents?.date)
                    })
            }
        }
        return entries.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    func add(title: String, due: Date?) throws {
        guard let list = store.defaultCalendarForNewReminders(), list.allowsContentModifications else {
            throw ReminderError(message: "Choose a writable default list in Apple Reminders.")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due { reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due) }
        try store.save(reminder, commit: true)
    }

    func complete(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }
}
