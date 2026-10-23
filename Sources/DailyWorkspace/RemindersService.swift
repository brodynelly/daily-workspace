import EventKit
import SwiftUI

struct ReminderEntry: Identifiable {
    let id: String
    let title: String
    let list: String
    let due: Date?
    let completed: Bool
}

@MainActor
final class RemindersService: ObservableObject {
    @Published private(set) var items: [ReminderEntry] = []
    @Published private(set) var authorized = false
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    private let store = EKEventStore()

    func connect() async {
        do {
            authorized = try await store.requestFullAccessToReminders()
            if authorized { await refresh() }
            else { error = "Allow Reminders access in System Settings → Privacy & Security." }
        } catch { self.error = error.localizedDescription }
    }

    func refresh() async {
        authorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        guard authorized else { return }
        loading = true
        error = nil
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        items = reminders.map { ReminderEntry(id: $0.calendarItemIdentifier, title: $0.title ?? "Untitled reminder", list: $0.calendar.title, due: $0.dueDateComponents?.date, completed: $0.isCompleted) }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        loading = false
    }

    func add(_ title: String, due: Date?) async -> Bool {
        guard authorized, let calendar = store.defaultCalendarForNewReminders(), calendar.allowsContentModifications else {
            error = "Choose a writable default Reminders list in Apple Reminders."
            return false
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        if let due { reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due) }
        do {
            try store.save(reminder, commit: true)
            await refresh()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func complete(_ item: ReminderEntry) async {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        do { try store.save(reminder, commit: true); await refresh() }
        catch { self.error = error.localizedDescription }
    }
}
