import AppKit
import DailyCore
import SwiftUI

/// Composition root and coordinator. Owns every store, wires system observers, and performs the
/// actions that span features (choosing a vault, opening notes, capture). Feature state lives in the stores.
@MainActor
final class AppModel: ObservableObject {
    struct Dependencies {
        /// The app's own folder (`~/.config/daily-workspace`), shown in Settings.
        var directory: WorkspaceDirectory
        var settings: SettingsPersisting
        /// Settings from earlier versions, imported once when no settings file exists yet.
        var legacyDefaults: UserDefaults?
        var makeTaskPersistence: () throws -> TaskPersisting
        var recovery: RecoveryStoring
        var keyStore: APIKeyStore
        var chatTransport: ChatTransport
        var calendarStore: CalendarStore
        var reminderStore: ReminderStore
        var autosaveDelay: Duration
        /// System notifications and the external-change poll. Off in tests.
        var observesSystem: Bool

        @MainActor static var live: Dependencies {
            let directory = WorkspaceDirectory.standard()
            do {
                try directory.prepare()
            } catch {
                Log.app.error(
                    "Workspace folder could not be created: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
                )
            }
            return Dependencies(
                directory: directory,
                settings: SettingsPersistence(url: directory.settingsURL),
                legacyDefaults: .standard,
                makeTaskPersistence: {
                    // Copy tasks from the old location once; the original file is left in place.
                    let legacy = WorkspaceDirectory.legacyFolder().appendingPathComponent("tasks.json")
                    if try WorkspaceDirectory.adopt(legacyFile: legacy, as: directory.tasksURL) {
                        Log.tasks.info("Copied tasks from the previous Application Support location")
                    }
                    return TaskPersistence(url: directory.tasksURL)
                },
                recovery: RecoveryStore(folder: directory.recoveryFolder),
                keyStore: KeychainAPIKeyStore(),
                chatTransport: OpenRouterClient(),
                calendarStore: EventKitCalendarStore(),
                reminderStore: EventKitReminderStore(),
                autosaveDelay: .milliseconds(800),
                observesSystem: true
            )
        }
    }

    enum CaptureDestination: String, CaseIterable, Identifiable {
        case task, note

        var id: String { rawValue }

        var title: String {
            switch self {
            case .task: return "Task for Today"
            case .note: return "Today's Note"
            }
        }
    }

    enum CaptureOutcome: Equatable {
        case captured
        case rejected(String)
    }

    let directory: WorkspaceDirectory
    let preferences: Preferences
    let navigation = AppNavigation()
    let vaultSession: VaultSession
    let document: NoteDocument
    let tasks: TaskStore
    let calendar: CalendarService
    let reminders: RemindersService
    let chat: ChatService

    @Published private(set) var systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Changes at midnight and on time-zone changes so "today" re-evaluates.
    @Published private(set) var dayTick = Date()

    private var pollTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    convenience init() {
        self.init(dependencies: .live)
    }

    init(dependencies: Dependencies) {
        directory = dependencies.directory
        preferences = Preferences(store: dependencies.settings, legacyDefaults: dependencies.legacyDefaults)
        vaultSession = VaultSession(preferences: preferences)
        document = NoteDocument(recovery: dependencies.recovery, autosaveDelay: dependencies.autosaveDelay)
        tasks = TaskStore(makePersistence: dependencies.makeTaskPersistence)
        chat = ChatService(keyStore: dependencies.keyStore, transport: dependencies.chatTransport)
        calendar = CalendarService(store: dependencies.calendarStore)
        reminders = RemindersService(store: dependencies.reminderStore)

        vaultSession.resolve()
        document.attach(vaultSession.vault)
        if vaultSession.vault != nil { openToday(create: false) }
        if dependencies.observesSystem { startObserving() }
    }

    deinit {
        pollTimer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }

    // MARK: Today

    var today: LocalDay {
        _ = dayTick
        return LocalDay(Date())
    }

    /// Vault-relative path of today's daily note, or nil when the template is invalid.
    var todayNotePath: String? {
        _ = dayTick
        return try? preferences.dailyNoteTemplate.relativePath(for: Date())
    }

    /// True only when the editor holds today's note, not whichever note was opened last.
    var isTodayNoteOpen: Bool {
        guard let path = todayNotePath else { return false }
        return document.relativePath == path
    }

    private var dailyNoteHeader: String { "# \(LocalDay(Date()))\n\n" }

    // MARK: Vault and notes

    func chooseVault() {
        guard let url = VaultSession.pickFolder() else { return }
        guard document.flushBeforeSwitching() else {
            navigation.section = .notes
            return
        }
        useVault(at: url)
    }

    /// Adopt `url` as the vault and open today's note if it exists.
    func useVault(at url: URL) {
        vaultSession.adopt(url)
        document.attach(vaultSession.vault)
        if vaultSession.vault != nil { openToday(create: false) }
    }

    /// Open (and by default create) today's note.
    func openToday(create: Bool = true, navigate: Bool = false) {
        if navigate { navigation.section = .notes }
        guard vaultSession.vault != nil else {
            document.post("Choose a vault first.")
            return
        }
        let path: String
        do {
            path = try preferences.dailyNoteTemplate.relativePath(for: Date())
        } catch {
            document.post(error.localizedDescription)
            return
        }
        guard document.flushBeforeSwitching() else { return }
        do {
            let result = try document.open(relativePath: path, createIfMissing: create, initialText: dailyNoteHeader)
            if result == .opened { preferences.rememberRecent(path) }
        } catch {
            Log.notes.error(
                "Opening today's note failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            document.post(error.localizedDescription)
        }
    }

    /// Open a vault-relative note in the editor.
    func openNote(_ path: String, navigate: Bool = true) {
        if navigate { navigation.section = .notes }
        guard vaultSession.vault != nil, document.flushBeforeSwitching() else { return }
        do {
            switch try document.open(relativePath: path, createIfMissing: false, initialText: "") {
            case .opened: preferences.rememberRecent(path)
            case .alreadyOpen: break
            case .missing: document.post("“\(path)” is no longer in the vault.")
            }
        } catch {
            Log.notes.error(
                "Opening a note failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            document.post(error.localizedDescription)
        }
    }

    /// AppKit's synchronous quit hook: false keeps the app open so the user can resolve the note.
    func prepareToQuit() -> Bool { document.flushBeforeSwitching() }

    // MARK: Capture

    /// Save a thought as a task due today, or append it to today's note without switching the open note.
    /// `.captured` means the text is on disk; on `.rejected` nothing was kept, so the form keeps the draft.
    func capture(_ raw: String, to destination: CaptureDestination) -> CaptureOutcome {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .rejected("Type something to capture.") }
        switch destination {
        case .task:
            return tasks.add(title: text, due: today)
                ? .captured : .rejected(tasks.message ?? "The task could not be saved.")
        case .note:
            return appendToTodayNote("- \(text)\n")
        }
    }

    private func appendToTodayNote(_ block: String) -> CaptureOutcome {
        guard let vault = vaultSession.vault else { return .rejected("Choose a vault to capture notes.") }
        let path: String
        do {
            path = try preferences.dailyNoteTemplate.relativePath(for: Date())
        } catch {
            return .rejected(error.localizedDescription)
        }
        if document.relativePath == path {
            if document.append(block) { return .captured }
            switch document.saveState {
            case .failed(let why): return .rejected("Today's note could not be saved: \(why)")
            default: return .rejected("Resolve the conflict on today's note in Notes first.")
            }
        }
        do {
            try vault.append(block, to: try vault.resolve(relativePath: path), creatingWith: dailyNoteHeader)
            Log.capture.info("Appended a capture to today's note on disk")
            return .captured
        } catch {
            Log.capture.error(
                "Capture to today's note failed: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            return .rejected("Could not add to today's note: \(error.localizedDescription)")
        }
    }

    // MARK: System observers

    private func startObserving() {
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) {
            $0.systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            observe(.default, name) {
                $0.dayTick = Date()
                $0.calendar.reload()
            }
        }
        observe(.default, NSApplication.didBecomeActiveNotification) { model in
            model.document.checkExternalChange()
            model.calendar.reload()
            model.reminders.updateStatus()
            if model.reminders.hasLoaded { Task { await model.reminders.refresh() } }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.document.checkExternalChange() }
        }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (AppModel) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if let self { handler(self) }
            }
        }
        observers.append((center, token))
    }
}

extension View {
    /// Inject the coordinator and every store a view may observe.
    func workspaceEnvironment(_ model: AppModel) -> some View {
        environmentObject(model)
            .environmentObject(model.navigation)
            .environmentObject(model.preferences)
            .environmentObject(model.vaultSession)
            .environmentObject(model.document)
            .environmentObject(model.tasks)
            .environmentObject(model.calendar)
            .environmentObject(model.reminders)
            .environmentObject(model.chat)
    }
}
