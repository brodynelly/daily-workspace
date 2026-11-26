import DailyCore
import Foundation

/// Runs the user's routines while the app is open: checks once a minute, runs at most one at a time in its own
/// Assistant session (so it never disturbs the open chat), and saves each run as a conversation. A run missed
/// while the Mac slept or the app was closed happens once on the next check, not once per missed slot.
@MainActor
final class RoutineScheduler: ObservableObject {
    @Published private(set) var routines: [AgentRoutine] = []
    /// The routine running now.
    @Published private(set) var running: UUID?
    @Published private(set) var storageError: String?

    private let store: RoutineStore?
    private let isEnabled: () -> Bool
    /// A fresh session for one run, wired like the main one (provider, limits, workspace, saving); nil when the
    /// Assistant cannot run. Set by `AppModel` once it is built.
    var makeSession: ((_ origin: String) -> AssistantSession?)?
    private let now: () -> Date
    private let calendar: Calendar
    private var timer: Timer?
    private var task: Task<Void, Never>?
    /// The running routine's session, so turning the Assistant off stops it mid-run.
    private var session: AssistantSession?

    init(
        store: RoutineStore?, isEnabled: @escaping () -> Bool, now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.isEnabled = isEnabled
        self.now = now
        self.calendar = calendar
        do {
            routines = try store?.load() ?? []
        } catch {
            Log.assistant.error("Routines could not be read: \(Log.code(error), privacy: .public)")
            storageError = "Routines could not be read."
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Check for due routines every minute, starting now.
    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancelRunning()
    }

    /// Stop the running routine's request at once (the Assistant was turned off): no further tool calls or
    /// provider requests happen after consent is withdrawn.
    func cancelRunning() {
        session?.setEnabled(false)
    }

    /// Start the first due routine, unless one is running or routines are off.
    func tick() {
        guard isEnabled(), running == nil else { return }
        let date = now()
        guard let due = routines.first(where: { $0.isDue(at: date, calendar: calendar) }) else { return }
        run(due.id)
    }

    /// Run a routine now (the Run now button, or when it is due).
    func run(_ id: UUID) {
        guard running == nil, let index = routines.firstIndex(where: { $0.id == id }) else { return }
        let routine = routines[index]
        // Recorded before the run so a crash or a failure can't make it run again on every check.
        routines[index].lastRunAt = now()
        persist()
        guard let session = makeSession?("routine: \(routine.name)") else {
            finish(id, outcome: "The Assistant is off or has no API key.", conversation: nil)
            return
        }
        running = id
        self.session = session
        session.send(Self.question(for: routine, at: now(), calendar: calendar))
        task = Task { [weak self] in
            await session.waitForCompletion()
            guard let self else { return }
            let outcome = session.error ?? (session.turns.isEmpty ? "stopped" : "answered")
            self.finish(id, outcome: outcome, conversation: session.turns.isEmpty ? nil : session.conversationID)
        }
    }

    // MARK: Editing

    @discardableResult
    func add(name: String, prompt: String, schedule: RoutineSchedule) -> AgentRoutine? {
        guard routines.count < AgentRoutine.maxRoutines else {
            storageError = "You can keep up to \(AgentRoutine.maxRoutines) routines."
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let routine = AgentRoutine(
            name: trimmed.isEmpty ? "Routine" : trimmed, prompt: prompt, schedule: schedule, createdAt: now())
        routines.append(routine)
        persist()
        return routine
    }

    func update(_ routine: AgentRoutine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index] = routine
        persist()
    }

    func delete(_ id: UUID) {
        routines.removeAll { $0.id == id }
        persist()
    }

    // MARK: Internals

    /// The routine's prompt, framed so the model knows nobody is watching and must report what it did.
    static func question(for routine: AgentRoutine, at date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let time = formatter.string(from: date)
        return """
            Scheduled routine "\(routine.name)" (\(routine.schedule.summary)), running at \(time) while Brody \
            is away. Do what it asks, using the tools; then report briefly what you did, which changes \
            were applied or are waiting for his review, and anything that needs his attention.

            \(routine.prompt)
            """
    }

    private func finish(_ id: UUID, outcome: String, conversation: UUID?) {
        running = nil
        task = nil
        session = nil
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].lastOutcome = outcome
        if let conversation { routines[index].lastConversationID = conversation }
        persist()
        Log.assistant.info("Routine run finished: \(outcome == "answered" ? "answered" : "failed", privacy: .public)")
    }

    private func persist() {
        do {
            try store?.save(routines)
            storageError = nil
        } catch {
            Log.assistant.error("Routines could not be saved: \(Log.code(error), privacy: .public)")
            storageError = "Routines could not be saved."
        }
    }
}
