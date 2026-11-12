import DailyCore
import Foundation

protocol TaskPersisting {
    func load() throws -> TaskList
    func save(_ list: TaskList) throws
}

extension TaskPersistence: TaskPersisting {}

/// App-owned tasks plus their persistence and undo. Transitions themselves live in `TaskList`.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks = TaskList()
    @Published private(set) var message: String?
    @Published private(set) var recentlyDeleted: TaskItem?

    private let persistence: TaskPersisting?

    init(makePersistence: () throws -> TaskPersisting) {
        var store: TaskPersisting?
        do {
            let made = try makePersistence()
            store = made
            tasks = try made.load()
        } catch {
            Log.tasks.error(
                "Tasks could not be loaded: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            message = "Tasks could not be loaded: \(error.localizedDescription)"
        }
        persistence = store
    }

    /// Add a task. Returns true only when it was saved; an unsaved add is rolled back and reported.
    @discardableResult
    func add(title: String, due: LocalDay?) -> Bool {
        var added = false
        return commit { added = $0.add(title: title, due: due) != nil } && added
    }

    func toggle(_ task: TaskItem) {
        commit { list in
            if task.isCompleted { list.reopen(id: task.id) } else { list.complete(id: task.id) }
        }
    }

    func edit(id: UUID, title: String, due: LocalDay?, noteLink: String?) {
        commit { $0.edit(id: id, title: title, due: due, noteLink: noteLink) }
    }

    func link(_ task: TaskItem, toNote path: String) {
        edit(id: task.id, title: task.title, due: task.due, noteLink: path)
    }

    func delete(_ task: TaskItem) {
        var removed: TaskItem?
        if commit({ removed = $0.remove(id: task.id) }) { recentlyDeleted = removed }
    }

    func undoDelete() {
        guard let item = recentlyDeleted else { return }
        if commit({ $0.restore(item) }) { recentlyDeleted = nil }
    }

    func dismissUndo() { recentlyDeleted = nil }

    /// Apply `change` and save. On failure the list is restored, so the screen never shows a change that
    /// would vanish on relaunch. Returns true when the change is on disk.
    @discardableResult
    private func commit(_ change: (inout TaskList) -> Void) -> Bool {
        var next = tasks
        change(&next)
        guard next != tasks else { return true }
        guard let persistence else {
            message = "Tasks are not being saved: storage is unavailable."
            return false
        }
        do {
            try persistence.save(next)
        } catch {
            Log.tasks.error(
                "Tasks could not be saved: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            message = "Tasks could not be saved: \(error.localizedDescription)"
            return false
        }
        tasks = next
        message = nil
        return true
    }
}
