import Foundation

/// Apple Reminders: incomplete items, add to the default list, complete. Separate from local Tasks.
@MainActor
final class RemindersService: ObservableObject {
    @Published private(set) var status: PermissionStatus = .notRequested
    @Published private(set) var items: [ReminderEntry] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    @Published private(set) var hasLoaded = false

    private let store: ReminderStore

    init(store: ReminderStore) {
        self.store = store
        updateStatus()
    }

    func updateStatus() {
        status = store.authorization
    }

    /// Call only in response to the user's action.
    func requestAccess() async {
        do {
            try await store.requestAccess()
        } catch {
            Log.reminders.error(
                "Reminders access request failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            status = .unavailable
            return
        }
        await refresh()
    }

    func refresh() async {
        updateStatus()
        guard status == .authorized else {
            items = []
            return
        }
        loading = true
        defer { loading = false }
        items = await store.incompleteReminders()
        hasLoaded = true
    }

    /// Returns true when the reminder was saved.
    func add(_ title: String, due: Date?) async -> Bool {
        guard status == .authorized else { return false }
        do {
            try store.add(title: title, due: due)
        } catch {
            Log.reminders.error(
                "Reminder save failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            self.error = error.localizedDescription
            return false
        }
        error = nil
        await refresh()
        return true
    }

    func complete(_ item: ReminderEntry) async {
        do {
            try store.complete(id: item.id)
        } catch {
            Log.reminders.error(
                "Reminder complete failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            self.error = error.localizedDescription
            return
        }
        error = nil
        await refresh()
    }
}
