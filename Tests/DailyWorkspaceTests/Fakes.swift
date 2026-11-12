import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

struct TestFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String = "injected failure") { errorDescription = message }
}

final class InMemoryTaskPersistence: TaskPersisting {
    var stored = TaskList()
    var failSaves = false
    private(set) var saveCount = 0

    func load() throws -> TaskList { stored }

    func save(_ list: TaskList) throws {
        if failSaves { throw TestFailure("disk full") }
        saveCount += 1
        stored = list
    }
}

final class InMemorySettings: SettingsPersisting {
    var stored: WorkspaceSettings?
    var loadError: Error?
    private(set) var saveCount = 0

    func load() throws -> WorkspaceSettings? {
        if let loadError { throw loadError }
        return stored
    }

    func save(_ settings: WorkspaceSettings) throws {
        saveCount += 1
        stored = settings
    }
}

final class FakeRecovery: RecoveryStoring {
    var folder: URL?
    var fails = false
    private(set) var stashed: [(label: String, text: String)] = []

    func stash(_ text: String, label: String) throws {
        if fails { throw TestFailure("recovery folder not writable") }
        stashed.append((label, text))
    }
}

final class FakeKeyStore: APIKeyStore {
    var key: String?
    var readError: Error?

    func read() throws -> String? {
        if let readError { throw readError }
        return key
    }

    func save(_ key: String) throws { self.key = key.isEmpty ? nil : key }
}

final class FakeTransport: ChatTransport {
    struct Request {
        let messages: [ChatMessage]
        let model: String?
        let apiKey: String
    }

    var reply: Result<String, Error> = .success("ok")
    private(set) var requests: [Request] = []

    func complete(_ messages: [ChatMessage], model: String?, apiKey: String) async throws -> String {
        requests.append(Request(messages: messages, model: model, apiKey: apiKey))
        return try reply.get()
    }
}

/// A fresh empty directory, removed after the test.
func makeTemporaryVault(_ testCase: XCTestCase) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "vault-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    testCase.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

func contents(of url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

@MainActor
final class FakeCalendarStore: CalendarStore {
    var authorization: PermissionStatus = .authorized
    var onChange: (() -> Void)?
    var calendars = [CalendarChoice(id: "home", title: "Home")]
    var eventsByDayStart: [Date: [AgendaEvent]] = [:]
    var failSaves = false
    private(set) var fetchedRanges: [(start: Date, end: Date)] = []
    private(set) var saved: [EventDraft] = []

    func requestAccess() async throws { authorization = .authorized }
    func writableCalendars() -> [CalendarChoice] { calendars }

    func events(from start: Date, to end: Date) -> [AgendaEvent] {
        fetchedRanges.append((start, end))
        return eventsByDayStart[start] ?? []
    }

    func save(_ draft: EventDraft) throws {
        if failSaves { throw CalendarError(message: "Calendar is read-only.") }
        saved.append(draft)
    }

    func deleteEvent(identifier: String) throws {}
}

@MainActor
final class FakeReminderStore: ReminderStore {
    var authorization: PermissionStatus = .authorized
    var reminders: [ReminderEntry] = []
    var addError: Error?
    private(set) var fetchCount = 0

    func requestAccess() async throws { authorization = .authorized }

    func incompleteReminders() async -> [ReminderEntry] {
        fetchCount += 1
        return reminders
    }

    func add(title: String, due: Date?) throws {
        if let addError { throw addError }
        reminders.append(ReminderEntry(id: UUID().uuidString, title: title, list: "Inbox", due: due))
    }

    func complete(id: String) throws { reminders.removeAll { $0.id == id } }
}

extension AppModel.Dependencies {
    /// Isolated dependencies: in-memory settings and stores, no legacy import, no system observers.
    /// The app folder defaults to a fresh, unused temporary path per call, so app-owned files (associations, the
    /// Luuna host file) never leak between tests.
    @MainActor
    static func test(
        tasks: InMemoryTaskPersistence = InMemoryTaskPersistence(),
        settings: InMemorySettings = InMemorySettings(),
        directory: WorkspaceDirectory? = nil,
        reminderStore: FakeReminderStore? = nil,
        luunaReader: FakeLuunaReader = FakeLuunaReader(),
        luunaKeys: FakeKeyStore = FakeKeyStore(),
        agentTransport: FakeAgentTransport = FakeAgentTransport(),
        assistantKeys: FakeKeyStore = FakeKeyStore(),
        calendarStore: FakeCalendarStore? = nil,
        configure: (inout WorkspaceSettings) -> Void = { _ in }
    ) -> Self {
        var initial = settings.stored ?? WorkspaceSettings()
        configure(&initial)
        settings.stored = initial
        return Self(
            directory: directory
                ?? WorkspaceDirectory(
                    url: FileManager.default.temporaryDirectory.appendingPathComponent(
                        "daily-workspace-tests-\(UUID().uuidString)")),
            settings: settings,
            legacyDefaults: nil,
            makeTaskPersistence: { tasks },
            recovery: FakeRecovery(),
            keyStore: FakeKeyStore(),
            chatTransport: FakeTransport(),
            calendarStore: calendarStore ?? FakeCalendarStore(),
            reminderStore: reminderStore ?? FakeReminderStore(),
            luunaReader: luunaReader,
            luunaKeyStore: luunaKeys,
            agentTransport: agentTransport,
            assistantKeyStore: assistantKeys,
            autosaveDelay: .seconds(60),
            observesSystem: false
        )
    }
}
