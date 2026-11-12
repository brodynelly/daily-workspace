import Foundation

public struct TaskItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    /// Vault-relative path of a linked note, if any.
    public var noteLink: String?
    public var created: Date
    public var updated: Date
    public var due: LocalDay?
    public var completedAt: Date?

    public var isCompleted: Bool { completedAt != nil }
}

/// App-owned tasks. Pure value type so every transition is unit-testable.
public struct TaskList: Codable, Equatable {
    public private(set) var items: [TaskItem]

    public init(items: [TaskItem] = []) {
        self.items = items
    }

    @discardableResult
    public mutating func add(title: String, due: LocalDay? = nil, noteLink: String? = nil, now: Date = Date())
        -> TaskItem?
    {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = TaskItem(
            id: UUID(), title: trimmed, noteLink: noteLink, created: now, updated: now, due: due, completedAt: nil)
        items.append(item)
        return item
    }

    public mutating func edit(id: UUID, title: String, due: LocalDay?, noteLink: String?, now: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items[i].title = trimmed }
        items[i].due = due
        items[i].noteLink = noteLink
        items[i].updated = now
    }

    public mutating func complete(id: UUID, now: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].completedAt == nil else { return }
        items[i].completedAt = now
        items[i].updated = now
    }

    public mutating func reopen(id: UUID, now: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].completedAt != nil else { return }
        items[i].completedAt = nil
        items[i].updated = now
    }

    @discardableResult
    public mutating func remove(id: UUID) -> TaskItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    /// Put a removed task back (undo).
    public mutating func restore(_ item: TaskItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
    }

    /// Open tasks due today or earlier (overdue stays visible), oldest due date first.
    public func dueToday(_ day: LocalDay) -> [TaskItem] {
        items
            .filter { !$0.isCompleted && ($0.due.map { $0 <= day } ?? false) }
            .sorted { ($0.due!, $0.created) < ($1.due!, $1.created) }
    }

    /// Open tasks with no due date.
    public var inbox: [TaskItem] {
        items.filter { !$0.isCompleted && $0.due == nil }.sorted { $0.created < $1.created }
    }

    /// Open tasks due after today.
    public func upcoming(after day: LocalDay) -> [TaskItem] {
        items
            .filter { !$0.isCompleted && ($0.due.map { $0 > day } ?? false) }
            .sorted { ($0.due!, $0.created) < ($1.due!, $1.created) }
    }

    public var completed: [TaskItem] {
        items.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
}
