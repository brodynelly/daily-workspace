import AppKit
import Combine
import Foundation

/// An event is identified by its window and the OpenCode attention generation, not by the window ID alone.
struct QuickPanelAttentionIdentity: Hashable, Sendable {
    let id: UInt64
    let instance: String
    let generation: UInt64
    let reason: String
}

/// Values come from the Kitty agent inventory. Unknown status is kept verbatim, not inferred.
struct QuickPanelAgent: Decodable, Equatable, Sendable, Identifiable {
    let id: UInt64
    let kind: String
    let kindLabel: String
    let title: String
    let opencodeTitle: String
    let sessionName: String
    let cwd: String
    let focused: Bool
    let status: String
    let reason: String
    let instance: String
    let generation: UInt64

    enum CodingKeys: String, CodingKey {
        case id, kind, title, cwd, focused, status, reason, instance, generation
        case kindLabel = "kind_label"
        case opencodeTitle = "opencode_title"
        case sessionName = "session_name"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UInt64.self, forKey: .id)
        status = try values.decode(String.self, forKey: .status)
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kindLabel = try values.decodeIfPresent(String.self, forKey: .kindLabel) ?? ""
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        opencodeTitle = try values.decodeIfPresent(String.self, forKey: .opencodeTitle) ?? ""
        sessionName = try values.decodeIfPresent(String.self, forKey: .sessionName) ?? ""
        cwd = try values.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        focused = try values.decodeIfPresent(Bool.self, forKey: .focused) ?? false
        reason = try values.decodeIfPresent(String.self, forKey: .reason) ?? ""
        instance = try values.decodeIfPresent(String.self, forKey: .instance) ?? ""
        generation = try values.decodeIfPresent(UInt64.self, forKey: .generation) ?? 0
    }

    var identity: QuickPanelAttentionIdentity {
        QuickPanelAttentionIdentity(id: id, instance: instance, generation: generation, reason: reason)
    }

    var displayTitle: String { opencodeTitle.isEmpty ? title : opencodeTitle }
}

struct QuickPanelAttentionRow: Equatable, Identifiable, Sendable {
    let agent: QuickPanelAgent
    let waitingSince: Date

    var id: QuickPanelAttentionIdentity { agent.identity }
}

enum QuickPanelAttentionSourceState: Equatable, Sendable {
    case notRead
    case missing
    case unavailable
    case invalid
    case empty
    case populated
}

enum QuickPanelAttentionAction: String, Sendable {
    case preview = "--text"
    case focus = "--focus"
    case dismiss = "--ack"
}

enum QuickPanelAttentionError: Error, Equatable, LocalizedError {
    case noLongerAvailable
    case invalidPreview

    var errorDescription: String? {
        switch self {
        case .noLongerAvailable: "This agent is no longer asking for attention."
        case .invalidPreview: "The agent's terminal preview is not UTF-8."
        }
    }
}

/// Replaces the QAP helper's shell interpolation with a fixed executable and separate argv fields.
struct QuickPanelAttentionHelper: Sendable {
    let invoke: @Sendable (QuickPanelAttentionAction, UInt64) async throws -> String

    static func live(
        script: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("github/dotfiles-mac/kitty/scripts/kitty-opencode-sessions.sh"),
        runner: QuickPanelCommandRunner = QuickPanelCommandRunner()
    ) -> Self {
        Self { action, id in
            let output = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/bash"),
                arguments: [script.path, action.rawValue, String(id)]
            )
            guard output.exitStatus == 0 else { throw QuickPanelCommandError.exited(output.exitStatus) }
            guard let text = String(data: output.stdout, encoding: .utf8) else {
                throw QuickPanelAttentionError.invalidPreview
            }
            return text
        }
    }
}

private enum QuickPanelAttentionReadResult: Sendable {
    case success([QuickPanelAgent])
    case failure(QuickPanelAttentionSourceState)
}

/// Reads the user-owned SketchyBar inventory without writing to it. A missing, unreadable or malformed
/// source never masquerades as an empty agent list. The first *valid* snapshot is a startup baseline.
@MainActor
final class QuickPanelAttention: ObservableObject {
    nonisolated static let defaultFileURL = URL(fileURLWithPath: "/tmp/sketchybar-opencode-agents.json")
    private static let maximumBytes = 2 * 1024 * 1024

    @Published private(set) var sourceState: QuickPanelAttentionSourceState = .notRead
    @Published private(set) var agents: [QuickPanelAgent] = []
    @Published private(set) var rows: [QuickPanelAttentionRow] = []

    /// Called only for unfocused attention first observed after the initial valid snapshot.
    var onNewAttention: (([QuickPanelAttentionRow]) -> Void)?

    private let fileURL: URL
    private let helper: QuickPanelAttentionHelper
    private let pollInterval: TimeInterval
    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var sleepObserver: NSObjectProtocol?
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    private var reading: Task<Void, Never>?
    private var readingRevision: UInt64?
    private var starting = false
    private var wantsWatching = false
    private var sleeping = false
    private var revision: UInt64 = 0
    private var needsWakeBaseline = false
    private var hasBaseline = false
    private var seen: Set<QuickPanelAttentionIdentity> = []
    private var waitingSince: [QuickPanelAttentionIdentity: Date] = [:]

    var isWatching: Bool { timer != nil }

    init(
        fileURL: URL = defaultFileURL,
        helper: QuickPanelAttentionHelper = .live(),
        pollInterval: TimeInterval = 1,
        observesSleep: Bool = true
    ) {
        self.fileURL = fileURL
        self.helper = helper
        self.pollInterval = pollInterval
        if observesSleep {
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.suspendForSleep() } }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.setSleeping(false) }
            }
        }
    }

    deinit {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        timer?.invalidate()
    }

    /// Sleep stops the watcher immediately. Wake reads a fresh baseline before reinstalling the timer.
    func setSleeping(_ sleeping: Bool) async {
        guard self.sleeping != sleeping else { return }
        if sleeping {
            suspendForSleep()
        } else {
            self.sleeping = false
            if wantsWatching { await start() }
        }
    }

    private func suspendForSleep() {
        guard !sleeping else { return }
        sleeping = true
        revision &+= 1
        needsWakeBaseline = true
        stopTimer()
    }

    /// Baselines before installing the watcher so existing attention cannot open the panel at launch.
    /// A manual stop stays stopped across sleep and wake; only a started watcher resumes.
    func start() async {
        wantsWatching = true
        guard timer == nil, !starting, !sleeping else { return }
        starting = true
        let startingRevision = revision
        await refresh()
        guard wantsWatching, starting, !sleeping, revision == startingRevision else { return }
        starting = false
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    func stop() {
        wantsWatching = false
        stopTimer()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        starting = false
    }

    /// Can also be called by panel Refresh. Reads made before sleep never supply a wake baseline.
    func refresh() async {
        guard !sleeping else { return }
        if let reading {
            let readingRevision = readingRevision
            await reading.value
            if readingRevision != revision, !sleeping { await refresh() }
            return
        }
        let readRevision = revision
        let fileURL = fileURL
        let maximumBytes = Self.maximumBytes
        let readTask = Task.detached(priority: .utility) {
            do {
                let handle = try FileHandle(forReadingFrom: fileURL)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
                guard data.count <= maximumBytes else { return QuickPanelAttentionReadResult.failure(.invalid) }
                return .success(try JSONDecoder().decode([QuickPanelAgent].self, from: data))
            } catch is DecodingError {
                return .failure(.invalid)
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain
                    && (nsError.code == CocoaError.Code.fileNoSuchFile.rawValue
                        || nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue)
                    || nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
                {
                    return .failure(.missing)
                }
                return .failure(.unavailable)
            }
        }
        let task = Task { @MainActor [weak self] in
            let result = await readTask.value
            if let self {
                if self.revision == readRevision, !self.sleeping { self.accept(result) }
                self.reading = nil
                self.readingRevision = nil
            }
        }
        readingRevision = readRevision
        reading = task
        await task.value
    }

    private func accept(_ result: QuickPanelAttentionReadResult) {
        switch result {
        case .success(let inventory):
            if needsWakeBaseline || sourceState != (inventory.isEmpty ? .empty : .populated) || agents != inventory {
                apply(inventory)
            }
            needsWakeBaseline = false
        case .failure(let state):
            sourceState = state
            // Do not clear the identity baseline during a transient failure; a recovered file is not new attention.
            agents = []
            rows = []
        }
    }

    /// All agents includes the native `unknown` statuses, with no synthesized busy or idle state.
    func allAgents() -> [QuickPanelAgent] { agents }

    /// The helper returns the screen; only its last 40 lines are exposed to the panel.
    func preview(_ identity: QuickPanelAttentionIdentity) async throws -> String {
        guard rows.contains(where: { $0.id == identity }) else { throw QuickPanelAttentionError.noLongerAvailable }
        let text = try await helper.invoke(.preview, identity.id)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last == "" { lines.removeLast() }
        return lines.suffix(40).joined(separator: "\n")
    }

    /// Focusing acknowledges in the owner helper; the panel should hide and restore focus after success.
    func goToAgent(_ identity: QuickPanelAttentionIdentity) async throws {
        await refresh()
        guard rows.contains(where: { $0.id == identity }) else { throw QuickPanelAttentionError.noLongerAvailable }
        _ = try await helper.invoke(.focus, identity.id)
        await refresh()
    }

    /// Dismissal acknowledges at the owner and refreshes; it never edits the inventory file locally.
    func dismiss(_ identity: QuickPanelAttentionIdentity) async throws {
        await refresh()
        guard rows.contains(where: { $0.id == identity }) else { throw QuickPanelAttentionError.noLongerAvailable }
        _ = try await helper.invoke(.dismiss, identity.id)
        await refresh()
    }

    private func apply(_ inventory: [QuickPanelAgent]) {
        let now = Date()
        let active = inventory.filter { $0.status == "attention" }
        let present = Set(active.map(\.identity))
        let fresh = active.filter { !seen.contains($0.identity) && !$0.focused }
        for agent in active where waitingSince[agent.identity] == nil {
            waitingSince[agent.identity] = now
        }
        waitingSince = waitingSince.filter { present.contains($0.key) }
        seen = present
        agents = inventory
        rows = active.map { QuickPanelAttentionRow(agent: $0, waitingSince: waitingSince[$0.identity] ?? now) }
        sourceState = inventory.isEmpty ? .empty : .populated
        if hasBaseline, !needsWakeBaseline, timer != nil, !fresh.isEmpty {
            let freshIDs = Set(fresh.map(\.identity))
            onNewAttention?(rows.filter { freshIDs.contains($0.id) })
        }
        hasBaseline = true
    }
}
