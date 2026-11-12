import AppKit
import Combine
import DailyCore
import SwiftUI

/// Composition root and coordinator. Owns every store, wires system observers, and performs the
/// actions that span features (choosing a vault, opening notes, capture). Feature state lives in the stores.
@MainActor
final class AppModel: ObservableObject {
    let directory: WorkspaceDirectory
    let preferences: Preferences
    let navigation = AppNavigation()
    let vaultSession: VaultSession
    let document: NoteDocument
    let tasks: TaskStore
    let calendar: CalendarService
    let reminders: RemindersService
    let chat: ChatService
    let luuna: LuunaStore
    let openLoops: OpenLoopsStore
    let projects: ProjectsStore
    let assistant: AssistantSession
    /// Whether an Anthropic key is saved, for Settings and the Assistant screen.
    let assistantKey: AssistantKey
    let restarts: RestartRecords
    let assistantContext: WorkspaceAssistantContext

    /// A problem with the saved Luuna settings (an unreadable token or host file), for Settings to show. Cleared by
    /// a successful `connectLuuna`.
    @Published var luunaSettingsNotice: String?

    @Published private(set) var systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Changes at midnight and on time-zone changes so "today" re-evaluates.
    @Published private(set) var dayTick = Date()

    private var pollTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Where the Luuna origin and token are saved (`AppModel+Sources.swift`).
    let luunaSettings: LuunaSettings
    /// Follows `vaultSession` for Open Loops and Projects (`AppModel+Sources.swift`).
    var vaultSubscription: AnyCancellable?
    /// The vault and `AGENTS.md` hash the Assistant's conversation started with (`AppModel+Assistant.swift`).
    var assistantAgentsFingerprint: String?
    var assistantSubscriptions: Set<AnyCancellable> = []

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
        luunaSettings = LuunaSettings(directory: dependencies.directory, keys: dependencies.luunaKeyStore)
        let saved = luunaSettings.load()
        luuna = LuunaStore(reader: dependencies.luunaReader, origin: saved.origin, token: saved.token)
        luunaSettingsNotice = saved.notice
        openLoops = OpenLoopsStore(tasks: tasks, reminders: reminders)
        projects = ProjectsStore(registry: AssociationRegistry(directory: dependencies.directory), luuna: luuna)
        let session = vaultSession
        let vaultRoot = { session.vault?.root }
        let ledger = RestartLedger(url: dependencies.directory.restartLedgerURL)
        assistantContext = WorkspaceAssistantContext(
            vaultRoot: vaultRoot, openLoops: openLoops, projects: projects, calendarStore: dependencies.calendarStore,
            ledger: ledger)
        assistantKey = AssistantKey(store: dependencies.assistantKeyStore)
        assistant = AssistantSession(
            transport: dependencies.agentTransport, keyStore: dependencies.assistantKeyStore,
            context: assistantContext, isEnabled: preferences.assistantEnabled)
        restarts = RestartRecords(ledger: ledger, vaultRoot: vaultRoot)

        vaultSession.resolve()
        document.attach(vaultSession.vault)
        if vaultSession.vault != nil { openToday(create: false) }
        observeAssistant()
        observeVault(refreshNow: dependencies.observesSystem)
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

    /// Vault-relative path of today's daily note, or nil without a vault or when it cannot be resolved.
    var todayNotePath: String? {
        _ = dayTick
        return try? resolveDailyNote(for: Date()).path
    }

    /// True only when the editor holds today's note, not whichever note was opened last.
    var isTodayNoteOpen: Bool {
        guard let path = todayNotePath else { return false }
        return document.relativePath == path
    }

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
        guard let vault = vaultSession.vault else {
            document.post("Choose a vault first.")
            return
        }
        let now = Date()
        let resolution: DailyNoteResolution
        do {
            resolution = try resolveDailyNote(for: now)
        } catch {
            document.post(error.localizedDescription)
            return
        }
        guard document.flushBeforeSwitching() else { return }
        do {
            let path = resolution.path
            let url = try vault.resolve(relativePath: path)
            let isNew = create && !vault.exists(url)
            let initialText = isNew ? newDailyNoteText(for: resolution, in: vault, date: now) : dailyNoteHeader
            let result = try document.open(relativePath: path, createIfMissing: create, initialText: initialText)
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
        let now = Date()
        let resolution: DailyNoteResolution
        do {
            resolution = try resolveDailyNote(for: now)
        } catch {
            return .rejected(error.localizedDescription)
        }
        let path = resolution.path
        if document.relativePath == path {
            if document.append(block) { return .captured }
            switch document.saveState {
            case .failed(let why): return .rejected("Today's note could not be saved: \(why)")
            default: return .rejected("Resolve the conflict on today's note in Notes first.")
            }
        }
        do {
            let url = try vault.resolve(relativePath: path)
            let initialText =
                vault.exists(url) ? dailyNoteHeader : newDailyNoteText(for: resolution, in: vault, date: now)
            try vault.append(block, to: url, creatingWith: initialText)
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
            // Open Loops re-reads Reminders (when allowed) along with the vault's Org, Seeds and Plot files.
            model.refreshSources()
            model.assistantContext.invalidateNotes()
            model.syncAssistantVaultAgents()
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

// MARK: Daily note

extension AppModel {
    /// Where the daily note for `date` lives under the current settings. Reads `.obsidian/daily-notes.json`
    /// fresh each time, so a change made in Obsidian applies at once. Throws a user-facing reason on refusal.
    func resolveDailyNote(for date: Date) throws -> DailyNoteResolution {
        guard let vault = vaultSession.vault else { throw VaultError.io("Choose a vault first.") }
        return try preferences.dailyNoteResolver.resolve(in: vault, for: date)
    }

    /// The vault's Obsidian daily-note settings for Settings to show: nil without a vault, `.success(nil)`
    /// when the vault has no `.obsidian/daily-notes.json`.
    var obsidianDailyNotes: Result<ObsidianDailyNotes?, Error>? {
        guard let vault = vaultSession.vault else { return nil }
        return Result { try ObsidianDailyNotes.load(from: vault) }
    }

    private var dailyNoteHeader: String { "# \(LocalDay(Date()))\n\n" }

    /// Text for a new daily note: the configured Obsidian template rendered for `date` when it can be read,
    /// otherwise the plain date header. The template file is only read, never written.
    private func newDailyNoteText(for resolution: DailyNoteResolution, in vault: NoteVault, date: Date) -> String {
        guard let templatePath = resolution.templatePath else { return dailyNoteHeader }
        do {
            guard let body = try ObsidianDailyNotes.readTemplate(at: templatePath, in: vault) else {
                Log.notes.notice("Daily-note template not found at \(templatePath, privacy: .private)")
                return dailyNoteHeader
            }
            return ObsidianDailyNotes.render(template: body, title: resolution.title, date: date)
        } catch {
            Log.notes.error(
                "Daily-note template could not be read: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            return dailyNoteHeader
        }
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
            .environmentObject(model.luuna)
            .environmentObject(model.openLoops)
            .environmentObject(model.projects)
            .environmentObject(model.assistant)
            .environmentObject(model.assistantKey)
            .environmentObject(model.restarts)
    }
}
