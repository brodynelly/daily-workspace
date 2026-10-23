import SwiftUI
import AppKit
import DailyCore

@MainActor
final class AppState: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case today = "Today", notes = "Notes", tasks = "Tasks", calendar = "Calendar", search = "Search", reminders = "Reminders", chat = "AI Chat"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .today: return "sun.max"
            case .notes: return "doc.text"
            case .tasks: return "checklist"
            case .calendar: return "calendar"
            case .search: return "magnifyingglass"
            case .reminders: return "list.bullet.circle"
            case .chat: return "bubble.left.and.bubble.right"
            }
        }
    }

    enum VaultState: Equatable {
        case notConfigured
        case available(URL)
        case needsReauthorization
        case unavailable(String)
    }

    enum SaveState: Equatable {
        case clean, dirty, saving, conflict
        case failed(String)
    }

    @Published var section: Section = .today
    @Published private(set) var vaultState: VaultState = .notConfigured
    @Published private(set) var noteText = ""
    @Published private(set) var noteURL: URL?
    @Published private(set) var saveState: SaveState = .clean
    @Published private(set) var noteMessage: String?
    @Published private(set) var tasks = TaskList()
    @Published private(set) var taskMessage: String?
    @Published private(set) var recentNotes: [String] = []
    @Published private(set) var recentlyDeleted: TaskItem?
    @Published private(set) var systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published private(set) var dayTick = Date() // changes at midnight / time zone change so "today" refreshes
    @Published var showQuickCapture = false
    @Published var showCommandPalette = false

    @Published var dailyFolder: String { didSet { defaults.set(dailyFolder, forKey: Keys.folder) } }
    @Published var dailyFilename: String { didSet { defaults.set(dailyFilename, forKey: Keys.filename) } }
    @Published var caretPreset: CaretPreset { didSet { defaults.set(caretPreset.rawValue, forKey: Keys.caret) } }

    let calendarService = CalendarService()
    let chatService = ChatService()

    private enum Keys {
        static let bookmark = "vaultBookmark"
        static let folder = "dailyFolder"
        static let filename = "dailyFilename"
        static let caret = "caretPreset"
        static let recents = "recentNotes"
    }

    private let defaults = UserDefaults.standard
    private var vault: NoteVault?
    private var snapshot: FileSnapshot?
    private var accessedURL: URL?
    private var saveTask: Task<Void, Never>?
    private var persistence: TaskPersistence?
    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    var today: LocalDay { _ = dayTick; return LocalDay(Date()) }
    var isConflict: Bool { saveState == .conflict }

    init() {
        let stored = UserDefaults.standard
        dailyFolder = stored.string(forKey: Keys.folder) ?? ""
        dailyFilename = stored.string(forKey: Keys.filename) ?? "YYYY-MM-DD"
        caretPreset = CaretPreset(rawValue: stored.string(forKey: Keys.caret) ?? "") ?? .glide
        recentNotes = stored.stringArray(forKey: Keys.recents) ?? []

        do {
            let p = TaskPersistence(url: try TaskPersistence.defaultURL())
            persistence = p
            tasks = try p.load()
        } catch {
            taskMessage = "Tasks could not be loaded: \(error.localizedDescription)"
        }

        resolveVault()
        calendarService.refresh(day: Date())
        startObserving()
    }

    // MARK: Observers

    private func startObserving() {
        let nc = NotificationCenter.default
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        })
        for name in [Notification.Name.NSCalendarDayChanged, NSNotification.Name.NSSystemTimeZoneDidChange] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.dayTick = Date()
                    self?.calendarService.refresh(day: Date())
                }
            })
        }
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.checkExternalChange()
                self?.calendarService.updateStatus()
                self?.calendarService.refresh(day: Date())
            }
        })
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkExternalChange() }
        }
    }

    // MARK: Vault access

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Vault"
        panel.message = "Choose the folder that holds your Obsidian vault."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            guard flushBeforeSwitching() else { return }
            defaults.set(data, forKey: Keys.bookmark)
            noteURL = nil
            noteText = ""
            snapshot = nil
            saveState = .clean
            resolveVault()
            openToday(create: false)
        } catch {
            vaultState = .unavailable("The folder could not be remembered: \(error.localizedDescription)")
        }
    }

    func resolveVault() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        vault = nil
        guard let data = defaults.data(forKey: Keys.bookmark) else {
            vaultState = .notConfigured
            return
        }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else {
                vaultState = .needsReauthorization
                return
            }
            accessedURL = url
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                vaultState = .unavailable("The vault folder is missing or has moved. Choose it again.")
                return
            }
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: Keys.bookmark)
            }
            vault = NoteVault(root: url)
            vaultState = .available(url)
            if noteURL == nil { openToday(create: false) }
        } catch {
            vaultState = .needsReauthorization
        }
    }

    // MARK: Notes

    func openToday(create: Bool = true) {
        guard let vault else {
            noteMessage = "Choose a vault in Settings first."
            return
        }
        guard flushBeforeSwitching() else { return }
        do {
            let rel = try DailyNoteTemplate(folder: dailyFolder, filename: dailyFilename).relativePath(for: Date())
            try open(relativePath: rel, in: vault, createIfMissing: create, initialText: "# \(LocalDay(Date()))\n\n")
        } catch {
            noteMessage = error.localizedDescription
        }
    }

    func openNote(relativePath: String) {
        guard let vault else { return }
        guard flushBeforeSwitching() else { return }
        do {
            try open(relativePath: relativePath, in: vault, createIfMissing: false, initialText: "")
        } catch {
            noteMessage = error.localizedDescription
        }
    }

    private func open(relativePath: String, in vault: NoteVault, createIfMissing: Bool, initialText: String) throws {
        let url = try vault.resolve(relativePath: relativePath)
        if url == noteURL { noteMessage = nil; return }
        let loaded: LoadedNote
        if vault.exists(url) {
            loaded = try vault.load(url)
        } else if createIfMissing {
            loaded = try vault.create(url, initialText: initialText)
        } else {
            return
        }
        noteURL = url
        noteText = loaded.text
        snapshot = loaded.snapshot
        saveState = .clean
        noteMessage = nil
        rememberRecent(relativePath)
    }

    private func flushBeforeSwitching() -> Bool {
        if saveState == .dirty || saveState == .saving { saveNow() }
        if saveState == .conflict {
            noteMessage = "Resolve the conflict on the open note first."
            return false
        }
        if case .failed = saveState {
            noteMessage = "The note could not be saved. Retry saving before opening another note."
            return false
        }
        return true
    }

    /// A synchronous termination hook must finish before AppKit exits.
    func prepareToQuit() -> Bool { flushBeforeSwitching() }

    var canSave: Bool {
        switch saveState {
        case .dirty, .failed: return true
        default: return false
        }
    }

    private func rememberRecent(_ path: String) {
        recentNotes.removeAll { $0 == path }
        recentNotes.insert(path, at: 0)
        recentNotes = Array(recentNotes.prefix(8))
        defaults.set(recentNotes, forKey: Keys.recents)
    }

    func userEdited(_ text: String) {
        guard text != noteText else { return }
        noteText = text
        guard saveState != .conflict else { return }
        saveState = .dirty
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        guard let vault, let url = noteURL, let snap = snapshot else { return }
        switch saveState {
        case .dirty, .failed: break
        default: return
        }
        saveState = .saving
        do {
            snapshot = try vault.save(noteText, to: url, expecting: snap)
            saveState = .clean
        } catch VaultError.conflict, VaultError.missing {
            saveState = .conflict
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    /// Poll for edits made by Obsidian, a sync client or anything else.
    private func checkExternalChange() {
        guard let vault, let url = noteURL, let snap = snapshot else { return }
        switch saveState {
        case .saving, .conflict: return
        default: break
        }
        do {
            guard let current = try vault.currentSnapshot(of: url) else {
                if saveState != .clean { saveState = .conflict } else { noteMessage = "The open note was removed from the vault." }
                return
            }
            guard current != snap else { return }
            if saveState == .clean {
                let loaded = try vault.load(url)
                noteText = loaded.text
                snapshot = loaded.snapshot
                noteMessage = "Updated from disk: the note changed outside the app."
            } else {
                saveState = .conflict
            }
        } catch {
            // Transient read failure (file locked mid-sync): try again on the next poll.
        }
    }

    /// Conflict choice 1: take the disk version. The local version is kept in the recovery folder first.
    func resolveConflictByReloading() {
        guard let vault, let url = noteURL else { return }
        RecoveryStore.stash(noteText, label: "my-version")
        do {
            let loaded = try vault.load(url)
            noteText = loaded.text
            snapshot = loaded.snapshot
            saveState = .clean
            noteMessage = "Reloaded from disk. Your version was saved to the recovery folder."
        } catch {
            noteMessage = error.localizedDescription
        }
    }

    /// Conflict choice 2: keep local text. The disk version is kept in the recovery folder first.
    func resolveConflictByKeepingMine() {
        guard let vault, let url = noteURL else { return }
        do {
            if let loaded = try? vault.load(url) { RecoveryStore.stash(loaded.text, label: "disk-version") }
            if let current = try vault.currentSnapshot(of: url) {
                snapshot = current
            } else {
                // File was deleted: recreate it from the local text.
                snapshot = try vault.create(url, initialText: noteText).snapshot
            }
            saveState = .dirty
            saveNow()
            noteMessage = "Kept your version. The other version was saved to the recovery folder."
        } catch {
            noteMessage = error.localizedDescription
        }
    }

    // MARK: Capture

    @discardableResult
    func capture(_ raw: String, asTask: Bool) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if asTask {
            addTask(title: text, due: today)
            return true
        }
        guard vault != nil else {
            noteMessage = "Choose a vault in Settings to capture notes."
            return false
        }
        guard flushBeforeSwitching() else { return false }
        openToday(create: true)
        guard noteMessage == nil, noteURL != nil, saveState != .conflict else { return false }
        var body = noteText
        if !body.isEmpty && !body.hasSuffix("\n") { body += "\n" }
        body += "- \(text)\n"
        userEdited(body)
        saveNow()
        // The text is now owned by the editor even if the disk write needs retrying.
        return true
    }

    // MARK: Tasks

    func addTask(title: String, due: LocalDay?) {
        guard tasks.add(title: title, due: due) != nil else { return }
        persistTasks()
    }

    func toggleTask(_ task: TaskItem) {
        if task.isCompleted { tasks.reopen(id: task.id) } else { tasks.complete(id: task.id) }
        persistTasks()
    }

    func editTask(id: UUID, title: String, due: LocalDay?, noteLink: String?) {
        tasks.edit(id: id, title: title, due: due, noteLink: noteLink)
        persistTasks()
    }

    func deleteTask(_ task: TaskItem) {
        recentlyDeleted = tasks.remove(id: task.id)
        persistTasks()
    }

    func undoDelete() {
        guard let item = recentlyDeleted else { return }
        tasks.restore(item)
        recentlyDeleted = nil
        persistTasks()
    }

    func dismissUndo() { recentlyDeleted = nil }

    func linkToOpenNote(_ task: TaskItem) {
        guard let vault, let url = noteURL, let rel = vault.relativePath(of: url) else { return }
        editTask(id: task.id, title: task.title, due: task.due, noteLink: rel)
    }

    private func persistTasks() {
        do {
            try persistence?.save(tasks)
            taskMessage = nil
        } catch {
            taskMessage = "Tasks could not be saved: \(error.localizedDescription)"
        }
    }
}

/// Where a discarded side of a conflict goes. Lives outside the vault so the vault stays untouched.
enum RecoveryStore {
    static func stash(_ text: String, label: String) {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return }
        let dir = base.appendingPathComponent("DailyWorkspace/Recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? Data(text.utf8).write(to: dir.appendingPathComponent("\(stamp)-\(label).md"), options: .atomic)
    }

    static var folder: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("DailyWorkspace/Recovery", isDirectory: true)
    }
}
