import AppKit
import XCTest

@testable import DailyWorkspace

@MainActor
private final class FakePanelTimer: QuickPanelTimerToken {
    let interval: TimeInterval
    let repeats: Bool
    private let action: @MainActor () -> Void
    private(set) var active = true

    init(interval: TimeInterval, repeats: Bool, action: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.repeats = repeats
        self.action = action
    }

    func cancel() { active = false }

    func fire() {
        guard active else { return }
        if !repeats { active = false }
        action()
    }
}

@MainActor
private final class FakePanelTimerScheduler: QuickPanelTimerScheduling {
    private(set) var timers: [FakePanelTimer] = []
    var activeTimers: [FakePanelTimer] { timers.filter(\.active) }

    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any QuickPanelTimerToken
    {
        let timer = FakePanelTimer(interval: interval, repeats: true, action: action)
        timers.append(timer)
        return timer
    }

    func once(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any QuickPanelTimerToken {
        let timer = FakePanelTimer(interval: interval, repeats: false, action: action)
        timers.append(timer)
        return timer
    }
}

@MainActor
private final class FakeBorder: QuickPanelBorderTracking {
    private(set) var running = false
    private(set) var starts = 0
    private(set) var refreshes = 0

    func start() {
        running = true
        starts += 1
    }
    func refresh() { if running { refreshes += 1 } }
    func stop() { running = false }
}

@MainActor
final class QuickPanelIntegrationsTests: XCTestCase {
    @MainActor
    private final class FakeClipboard: QuickPanelClipboardReading {
        var count = 1
        private(set) var reads = 0
        var changeCount: Int {
            reads += 1
            return count
        }
    }

    func testOptOutDoesNotReadClipboardOrStartTimers() {
        let clipboard = FakeClipboard()
        let scheduler = FakePanelTimerScheduler()
        let border = FakeBorder()
        let service = QuickPanelIntegrations(clipboard: clipboard, scheduler: scheduler, border: border)
        service.start()
        service.wake()

        XCTAssertEqual(clipboard.reads, 0)
        XCTAssertTrue(scheduler.activeTimers.isEmpty)
        XCTAssertFalse(border.running)
        service.stop()
    }

    func testExplicitClipboardFlashRespectsConsentAndDoesNotReadContents() {
        let clipboard = FakeClipboard()
        let scheduler = FakePanelTimerScheduler()
        let service = QuickPanelIntegrations(clipboard: clipboard, scheduler: scheduler, border: FakeBorder())
        var feedback: [Bool] = []
        service.onClipboardFeedback = { feedback.append($0) }
        service.start()
        XCTAssertFalse(service.flashClipboard())
        XCTAssertEqual(clipboard.reads, 0)
        service.setEnabled(clipboard: true, border: false)
        let reads = clipboard.reads
        XCTAssertTrue(service.flashClipboard())
        XCTAssertEqual(clipboard.reads, reads)
        XCTAssertEqual(feedback, [true])
        service.sleep()
        XCTAssertFalse(service.flashClipboard())
        XCTAssertEqual(feedback, [true, false])
        service.stop()
    }

    func testChangeCountOnlyFeedbackAndSleepWakeLifecycle() {
        let clipboard = FakeClipboard()
        let scheduler = FakePanelTimerScheduler()
        let border = FakeBorder()
        let service = QuickPanelIntegrations(
            clipboardEnabled: true, borderEnabled: true, clipboard: clipboard, scheduler: scheduler, border: border
        )
        var changes = 0
        var feedback: [Bool] = []
        service.onClipboardChange = { changes += 1 }
        service.onClipboardFeedback = { feedback.append($0) }

        service.start()
        service.start()  // Idempotent: no second poller.
        XCTAssertEqual(scheduler.activeTimers.map(\.interval), [0.15])
        XCTAssertEqual(clipboard.reads, 1)
        XCTAssertTrue(border.running)

        scheduler.activeTimers[0].fire()
        XCTAssertEqual(changes, 0)
        clipboard.count += 1
        scheduler.activeTimers[0].fire()
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(feedback, [true])
        XCTAssertEqual(scheduler.activeTimers.map(\.interval).sorted(), [0.15, 1])

        service.sleep()
        XCTAssertTrue(scheduler.activeTimers.isEmpty)
        XCTAssertFalse(border.running)
        XCTAssertEqual(feedback, [true, false])
        let readsAtSleep = clipboard.reads
        for timer in scheduler.timers { timer.fire() }
        XCTAssertEqual(clipboard.reads, readsAtSleep)

        clipboard.count += 1  // Changes during sleep are not replayed as a fresh copy.
        service.wake()
        XCTAssertEqual(scheduler.activeTimers.map(\.interval), [0.15])
        XCTAssertEqual(clipboard.reads, readsAtSleep + 1)
        scheduler.activeTimers[0].fire()
        XCTAssertEqual(changes, 1)
        clipboard.count += 1
        scheduler.activeTimers[0].fire()
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(feedback, [true, false, true])

        service.stop()
        XCTAssertTrue(scheduler.activeTimers.isEmpty)
        XCTAssertFalse(border.running)
        XCTAssertEqual(feedback.last, false)
    }

    func testDisablingWhileActiveStopsTimersAndRefreshesOnlyWhenOptedInAgain() {
        let scheduler = FakePanelTimerScheduler()
        let clipboard = FakeClipboard()
        let border = FakeBorder()
        let service = QuickPanelIntegrations(
            clipboardEnabled: true, borderEnabled: true, clipboard: clipboard, scheduler: scheduler, border: border
        )
        service.start()
        service.setEnabled(clipboard: false, border: false)
        XCTAssertTrue(scheduler.activeTimers.isEmpty)
        XCTAssertFalse(border.running)
        let reads = clipboard.reads
        service.sleep()
        service.wake()
        XCTAssertEqual(clipboard.reads, reads)
        service.setEnabled(clipboard: true, border: false)
        XCTAssertEqual(scheduler.activeTimers.map(\.interval), [0.15])
        XCTAssertFalse(border.running)
        service.stop()
    }

    func testEnvironmentOffSwitchOverridesBothOptIns() {
        let clipboard = FakeClipboard()
        let scheduler = FakePanelTimerScheduler()
        let border = FakeBorder()
        let service = QuickPanelIntegrations(
            clipboardEnabled: true, borderEnabled: true, clipboard: clipboard, scheduler: scheduler,
            border: border, environment: ["QAP_INTEGRATIONS": "0"]
        )
        service.start()
        service.sleep()
        service.wake()
        XCTAssertEqual(clipboard.reads, 0)
        XCTAssertTrue(scheduler.activeTimers.isEmpty)
        XCTAssertFalse(border.running)
        service.stop()
    }

    func testPaletteReloadRechecksOnlyEnabledAwakeKittyBorder() {
        let border = FakeBorder()
        let service = QuickPanelIntegrations(
            borderEnabled: true, border: border, environment: [:]
        )
        service.start()
        service.refreshPalette()
        XCTAssertEqual(border.refreshes, 1)
        service.sleep()
        service.refreshPalette()
        XCTAssertEqual(border.refreshes, 1)
        service.wake()
        service.refreshPalette()
        XCTAssertEqual(border.refreshes, 2)
        service.setEnabled(clipboard: false, border: false)
        service.refreshPalette()
        XCTAssertEqual(border.refreshes, 2)
        service.stop()

        let disabledBorder = FakeBorder()
        let disabled = QuickPanelIntegrations(
            borderEnabled: true, border: disabledBorder, environment: ["QAP_INTEGRATIONS": "0"]
        )
        disabled.start()
        disabled.refreshPalette()
        XCTAssertEqual(disabledBorder.refreshes, 0)
        disabled.stop()
    }

    func testKittyFallbackRunsOnlyWhileFrontmostAndEnabled() {
        let scheduler = FakePanelTimerScheduler()
        var front: (bundleID: String?, pid: pid_t)? = ("com.apple.Safari", 101)
        let border = KittyQuickAccessBorder(
            colorschemeURL: URL(fileURLWithPath: "/not-a-palette/active-colorscheme.sh"),
            scheduler: scheduler, frontmost: { front }, windows: { [] }, accessibilityTrusted: { false }
        )
        border.start()
        XCTAssertTrue(scheduler.activeTimers.isEmpty)
        front = ("net.kovidgoyal.kitty-quick-access", 102)
        border.refresh()
        border.refresh()
        XCTAssertEqual(scheduler.activeTimers.map(\.interval), [0.25])
        front = ("com.apple.Safari", 101)
        scheduler.activeTimers[0].fire()  // Poller itself cancels on a missed activation notification.
        XCTAssertTrue(scheduler.activeTimers.isEmpty)
        border.stop()
        XCTAssertTrue(scheduler.activeTimers.isEmpty)
    }

    func testKittyWatcherRebindsOnProcessChangeAndStopsWhileHidden() {
        let scheduler = FakePanelTimerScheduler()
        var front: (bundleID: String?, pid: pid_t)? = ("net.kovidgoyal.kitty-quick-access", 102)
        let border = KittyQuickAccessBorder(
            colorschemeURL: URL(fileURLWithPath: "/not-a-palette/active-colorscheme.sh"),
            scheduler: scheduler, frontmost: { front }, windows: { [] }, accessibilityTrusted: { false }
        )

        border.start()
        let first = scheduler.activeTimers[0]
        front = ("net.kovidgoyal.kitty-quick-access", 103)
        border.refresh()
        XCTAssertFalse(first.active)
        XCTAssertEqual(scheduler.activeTimers.map(\.interval), [0.25])

        border.stop()
        XCTAssertTrue(scheduler.activeTimers.isEmpty)
        border.refresh()
        XCTAssertTrue(scheduler.activeTimers.isEmpty)

        border.start()
        XCTAssertEqual(scheduler.activeTimers.map(\.interval), [0.25])
        border.stop()
    }

    func testWindowSelectionExcludesOtherProcessesAndInvisibleOrTinyWindows() {
        let unrelated = KittyQuickAccessWindow(
            ownerPID: 8, bounds: CGRect(x: 0, y: 0, width: 800, height: 500), layer: 1, alpha: 1)
        let hidden = KittyQuickAccessWindow(ownerPID: 7, bounds: unrelated.bounds, layer: 1, alpha: 0)
        let tiny = KittyQuickAccessWindow(
            ownerPID: 7, bounds: CGRect(x: 0, y: 0, width: 60, height: 60), layer: 1, alpha: 1)
        let target = KittyQuickAccessWindow(ownerPID: 7, bounds: unrelated.bounds, layer: 3, alpha: 1)

        XCTAssertNil(KittyQuickAccessWindow.target(in: [unrelated, hidden, tiny], frontmostPID: 7))
        XCTAssertEqual(KittyQuickAccessWindow.target(in: [unrelated, hidden, tiny, target], frontmostPID: 7)?.layer, 3)
    }

    func testColorschemeValueAndFallback() {
        let custom = KittyQuickAccessBorder.color(in: "bnelly_color02='#124578'\n")
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        custom.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0x12 / 255, accuracy: 0.001)
        XCTAssertEqual(green, 0x45 / 255, accuracy: 0.001)
        XCTAssertEqual(blue, 0x78 / 255, accuracy: 0.001)
        let fallback = KittyQuickAccessBorder.color(in: "bnelly_color02='#oops'\n")
        fallback.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0x37 / 255, accuracy: 0.001)
        XCTAssertEqual(green, 0xf4 / 255, accuracy: 0.001)
        XCTAssertEqual(blue, 0x99 / 255, accuracy: 0.001)
    }
}
