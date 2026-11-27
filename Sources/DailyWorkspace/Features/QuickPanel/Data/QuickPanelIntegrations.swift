import AppKit

@MainActor
protocol QuickPanelClipboardReading {
    var changeCount: Int { get }
}

@MainActor
protocol QuickPanelTimerToken {
    func cancel()
}

@MainActor
protocol QuickPanelTimerScheduling {
    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any QuickPanelTimerToken
    func once(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any QuickPanelTimerToken
}

@MainActor
protocol QuickPanelBorderTracking {
    func start()
    func refresh()
    func stop()
}

@MainActor
struct GeneralPasteboardCount: QuickPanelClipboardReading {
    var changeCount: Int { NSPasteboard.general.changeCount }
}

@MainActor
final class ScheduledPanelTimer: QuickPanelTimerToken {
    private var timer: Timer?

    init(interval: TimeInterval, repeats: Bool, action: @escaping @MainActor () -> Void) {
        // Timer blocks are `@Sendable`, but a timer scheduled here fires on the main run loop, so the main-actor
        // action is only ever called on the main actor.
        nonisolated(unsafe) let action = action
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer?.tolerance = repeats ? 0.05 : 0
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
struct PanelTimerScheduler: QuickPanelTimerScheduling {
    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any QuickPanelTimerToken
    {
        ScheduledPanelTimer(interval: interval, repeats: true, action: action)
    }

    func once(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any QuickPanelTimerToken {
        ScheduledPanelTimer(interval: interval, repeats: false, action: action)
    }
}

/// Optional, process-local integrations. `QAP_INTEGRATIONS=0` overrides both opt-ins.
/// No clipboard content is requested: only the pasteboard's monotonically changing count.
@MainActor
final class QuickPanelIntegrations {
    var onClipboardChange: (() -> Void)?
    /// The consumer (for example a SketchyBar bridge) decides how to publish this transient state.
    var onClipboardFeedback: ((Bool) -> Void)?

    private let clipboard: any QuickPanelClipboardReading
    private let scheduler: any QuickPanelTimerScheduling
    private let border: any QuickPanelBorderTracking
    private let environmentAllowsIntegrations: Bool
    private var clipboardEnabled: Bool
    private var borderEnabled: Bool
    private var started = false
    private var awake = true
    private var lastChangeCount: Int?
    private var clipboardTimer: (any QuickPanelTimerToken)?
    private var feedbackTimer: (any QuickPanelTimerToken)?
    private var feedbackVisible = false
    private var observers: [NSObjectProtocol] = []

    init(
        clipboardEnabled: Bool = false,
        borderEnabled: Bool = false,
        colorschemeURL: URL? = nil,
        clipboard: (any QuickPanelClipboardReading)? = nil,
        scheduler: (any QuickPanelTimerScheduling)? = nil,
        border: (any QuickPanelBorderTracking)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.clipboardEnabled = clipboardEnabled
        self.borderEnabled = borderEnabled
        self.clipboard = clipboard ?? GeneralPasteboardCount()
        let scheduler = scheduler ?? PanelTimerScheduler()
        self.scheduler = scheduler
        self.environmentAllowsIntegrations = environment["QAP_INTEGRATIONS"] != "0"
        self.border =
            border
            ?? KittyQuickAccessBorder(
                colorschemeURL: colorschemeURL ?? Self.defaultColorschemeURL(environment: environment),
                scheduler: scheduler
            )
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        let notifications: [(Notification.Name, @MainActor () -> Void)] = [
            (NSWorkspace.willSleepNotification, { [weak self] in self?.sleep() }),
            (NSWorkspace.didWakeNotification, { [weak self] in self?.wake() }),
            (NSWorkspace.didActivateApplicationNotification, { [weak self] in self?.border.refresh() }),
            (NSWorkspace.activeSpaceDidChangeNotification, { [weak self] in self?.border.refresh() }),
        ]
        for (name, action) in notifications {
            // Delivered on `.main`, so the main-actor action is only ever called on the main actor.
            nonisolated(unsafe) let action = action
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { action() }
                })
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.border.refresh() }
            })
        resumeEnabledIntegrations()
    }

    func stop() {
        guard started else { return }
        started = false
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        suspendIntegrations()
    }

    func setEnabled(clipboard: Bool, border: Bool) {
        guard clipboardEnabled != clipboard || borderEnabled != border else { return }
        clipboardEnabled = clipboard
        borderEnabled = border
        guard started else { return }
        suspendIntegrations()
        resumeEnabledIntegrations()
    }

    func sleep() {
        guard awake else { return }
        awake = false
        suspendIntegrations()
    }

    func wake() {
        guard !awake else { return }
        awake = true
        resumeEnabledIntegrations()
    }

    func refreshPalette() {
        guard started, awake, environmentAllowsIntegrations, borderEnabled else { return }
        border.refresh()
    }

    private func resumeEnabledIntegrations() {
        guard started, awake, environmentAllowsIntegrations else { return }
        if clipboardEnabled, clipboardTimer == nil {
            lastChangeCount = clipboard.changeCount
            clipboardTimer = scheduler.repeating(every: 0.15) { [weak self] in self?.pollClipboard() }
        }
        if borderEnabled { border.start() }
    }

    private func suspendIntegrations() {
        clipboardTimer?.cancel()
        clipboardTimer = nil
        feedbackTimer?.cancel()
        feedbackTimer = nil
        lastChangeCount = nil
        if feedbackVisible {
            feedbackVisible = false
            onClipboardFeedback?(false)
        }
        border.stop()
    }

    private func pollClipboard() {
        guard started, awake, clipboardEnabled, environmentAllowsIntegrations else { return }
        let count = clipboard.changeCount
        guard let lastChangeCount, count != lastChangeCount else { return }
        self.lastChangeCount = count
        onClipboardChange?()
        _ = flashClipboard()
    }

    @discardableResult
    func flashClipboard() -> Bool {
        guard started, awake, clipboardEnabled, environmentAllowsIntegrations else { return false }
        feedbackTimer?.cancel()
        feedbackVisible = true
        onClipboardFeedback?(true)
        feedbackTimer = scheduler.once(after: 1) { [weak self] in
            guard let self else { return }
            self.feedbackTimer = nil
            self.feedbackVisible = false
            self.onClipboardFeedback?(false)
        }
        return true
    }

    private static func defaultColorschemeURL(environment: [String: String]) -> URL {
        let root = environment["DOTFILES_DIR"] ?? NSHomeDirectory() + "/github/dotfiles-mac"
        return URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
            .appendingPathComponent("colorscheme/active/active-colorscheme.sh")
    }
}
