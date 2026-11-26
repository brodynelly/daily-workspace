import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import DailyCore
import SwiftUI

/// Routes shared by the reusable Pascal panel and its workspace actions.
enum QuickPanelRoute: String, CaseIterable, Identifiable {
    case home, agents, sessions, files, projects, workspaces, ssh, tmux, shortcuts, attention, system, monitor, music
    case calendar

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .agents: "Agent sessions"
        case .sessions: "Sessions"
        case .files: "Files"
        case .projects: "Projects"
        case .workspaces: "Workspaces"
        case .ssh: "SSH"
        case .tmux: "tmux"
        case .shortcuts: "Keyboard shortcuts"
        case .attention: "Attention"
        case .system: "System"
        case .monitor: "Monitor"
        case .music: "Turbo Music"
        case .calendar: "Calendar"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .agents: "sparkles.rectangle.stack"
        case .sessions: "terminal"
        case .files: "doc.text"
        case .projects: "folder"
        case .workspaces: "macwindow.on.rectangle"
        case .ssh: "network"
        case .tmux: "rectangle.split.2x1"
        case .shortcuts: "keyboard"
        case .attention: "bell.badge"
        case .system: "gearshape"
        case .monitor: "gauge.with.dots.needle.67percent"
        case .music: "music.note"
        case .calendar: "calendar"
        }
    }

    var workspaceSection: AppSection? {
        switch self {
        case .home, .system, .shortcuts: .today
        case .agents, .sessions, .tmux, .ssh: .assistant
        case .files: .notes
        case .projects, .workspaces: .projects
        case .attention: .openLoops
        case .calendar: .calendar
        case .music, .monitor: nil
        }
    }
}

/// One reusable panel; it does not own workspace stores or start another process.
@MainActor
final class QuickPanelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var currentRoute: QuickPanelRoute = .home
    @Published var rows: [QuickPanelDataRow] = []
    @Published var selectedIndex = 0
    @Published var query = "" { didSet { updateRows() } }
    @Published var shortcutTool: String?
    @Published var workspacePath: String?
    @Published var attentionPreview: String?
    @Published var focusedPane = "document"
    @Published var searchRequest = 0
    @Published var zoomed = false
    @Published private(set) var calendarSnapshot: QuickPanelCalendarSnapshot?
    @Published private(set) var music = QuickPanelMusic()
    @Published private(set) var musicLoading = false
    @Published private(set) var attention = QuickPanelAttention()
    private(set) var dataProvider = QuickPanelDataProvider()
    var actions = QuickPanelDataActions()
    var systemActions = QuickPanelSystemActions()
    @Published var workspaceRows: [QuickPanelDataRow] = []
    var model: AppModel?
    private var subscriptions: Set<AnyCancellable> = []
    var navigationHistory: [QuickPanelNavigationEntry] = []
    /// The first key of a pending vim sequence such as `gg` or `dd`.
    var pendingVimPrefix: Character?
    var refreshGeneration = 0
    var attentionIdentities: [String: QuickPanelAttentionIdentity] = [:]
    private var configuration = QuickPanelControlConfiguration()
    var panelFont: String { configuration.font }
    var menuRevision: Int = 0
    private(set) var error: String?
    var onErrorChange: ((String?) -> Void)?
    var onMusicAction: ((QuickPanelMusicAction) -> Void)?
    var openWorkspace: ((AppSection) -> Void)?
    let palette = QuickPanelCommandPalette(), assistantPane = QuickPanelAssistantPane()
    let insights = QuickPanelWorkspaceInsights(), monitor = QuickPanelMonitor()

    var isVisible: Bool { panel.isVisible }
    /// The search pane stays hidden until `?`, Find or typing asks for it; a live query keeps it on screen.
    var searchVisible: Bool { !zoomed && (focusedPane == "command" || !query.isEmpty) }
    var showsPreview: Bool {
        guard !zoomed else { return false }
        if currentRoute == .calendar || attentionPreview != nil { return true }
        return currentRoute == .agents && rows.indices.contains(selectedIndex)
            && rows[selectedIndex].nativeRunID != nil
    }
    var clipboardFeedbackEnabled: Bool {
        configuration.clipboardFeedback && model?.preferences.quickPanelClipboardEnabled == true
            && ProcessInfo.processInfo.environment["QAP_INTEGRATIONS"] != "0"
    }

    let panel: QuickPanelWindow
    private var previousApp: NSRunningApplication?
    private var previousWindow: AXUIElement?
    private weak var previousLocalWindow: NSWindow?
    private var activationObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?

    override init() {
        panel = QuickPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        super.init()
        panel.level = .modalPanel
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.escape() }
        installBackground()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                else { return }
                if self.configuration.zenMouse,
                    self.configuration.shouldCenterMouse(
                        applicationName: app.localizedName, accessibilityTrusted: AXIsProcessTrusted()),
                    let screen = NSScreen.main,
                    let point = Self.mouseTarget(
                        position: "center", visibleFrame: screen.visibleFrame,
                        primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY)
                {
                    CGWarpMouseCursorPosition(point)
                }
                guard self.isVisible else { return }
                self.hide(restoreFocus: false)
            }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.installBackground() }
        }
    }

    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    func show(_ route: QuickPanelRoute) {
        navigate(to: route)
        if !isVisible {
            capturePreviousFocus()
            positionPanelOnScreen()
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide(restoreFocus: false) }
            }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, self.isVisible, event.window === self.panel else { return false }
                    return self.handleKey(event)
                }
                return handled ? nil : event
            }
        }
        if !isVisible {
            dataProvider.startWatching { [weak self] change in
                guard let self else { return }
                switch change {
                case .shortcuts: self.updateRows()
                case .palette: self.installBackground()
                }
            }
            music.setVisible(route == .music)
            refresh()
        } else {
            music.setVisible(route == .music)
        }
        if route == .calendar { loadCalendar() }
        if route == .attention { Task { await attention.refresh() } }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func toggle(_ route: QuickPanelRoute) {
        if isVisible && currentRoute == route {
            hide(restoreFocus: true)
        } else {
            show(route)
        }
    }

    func hide(restoreFocus: Bool) {
        guard isVisible else { return }
        palette.close()
        dataProvider.stopWatching()
        dataProvider.cancelRefresh()
        refreshGeneration += 1
        music.setVisible(false)
        panel.orderOut(nil)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if restoreFocus {
            if let previousApp, !previousApp.isTerminated {
                previousApp.activate(options: [])
                if let previousWindow { AXUIElementPerformAction(previousWindow, kAXRaiseAction as CFString) }
            } else {
                previousLocalWindow?.makeKeyAndOrderFront(nil)
            }
        }
        previousApp = nil
        previousWindow = nil
        previousLocalWindow = nil
    }

    func reportError(_ message: String?) {
        error = message
        objectWillChange.send()
        onErrorChange?(message)
    }

    func open(_ section: AppSection) {
        hide(restoreFocus: false)
        openWorkspace?(section)
    }

    func configure(model: AppModel, configuration: QuickPanelControlConfiguration = .init()) {
        self.model = model
        self.configuration = configuration
        let dotfiles = URL(fileURLWithPath: configuration.dotfiles, isDirectory: true)
        dataProvider = QuickPanelDataProvider(dotfiles: dotfiles)
        actions = QuickPanelDataActions(dotfiles: dotfiles)
        attention.stop()
        attention = QuickPanelAttention(
            fileURL: URL(fileURLWithPath: configuration.attentionFile),
            helper: .live(
                script: dotfiles.appendingPathComponent(
                    "kitty/scripts/kitty-opencode-sessions.sh")))
        attention.onNewAttention = { [weak self] _ in
            guard let self, !self.isVisible else { return }
            self.show(.attention)
        }
        music.setVisible(false)
        music =
            configuration.musicFixture.map { path in
                QuickPanelMusic(transport: QuickPanelFixtureTransport(file: URL(fileURLWithPath: path)), preview: true)
            } ?? QuickPanelMusic()
        subscriptions.removeAll()
        dataProvider.$snapshot.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateRows() }
        }.store(in: &subscriptions)
        model.luunaWork.$runs.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateRows() }
        }.store(in: &subscriptions)
        model.luunaWork.$selectedRun.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateRows() }
        }.store(in: &subscriptions)
        model.luunaWork.follower.$events.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateRows() }
        }.store(in: &subscriptions)
        attention.$rows.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateRows() }
        }.store(in: &subscriptions)
        attention.$sourceState.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateRows() }
        }.store(in: &subscriptions)
        music.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateRows() }
        }.store(in: &subscriptions)
        Task { await attention.start() }
        installBackground()
        if isVisible { refresh() }
    }

    func loadCalendar() {
        calendarSnapshot = model?.calendar.todayAgenda()
        updateRows()
    }

    func reloadMusic() {
        guard !musicLoading else { return }
        musicLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.musicLoading = false }
            do {
                try await self.music.load()
                self.updateRows()
            } catch { self.reportError(error.localizedDescription) }
        }
    }

}

extension QuickPanelController {
    fileprivate func capturePreviousFocus() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        previousLocalWindow = previousApp == nil ? NSApp.keyWindow : nil
        previousWindow = nil
        if let previousApp, AXIsProcessTrusted() {
            let app = AXUIElementCreateApplication(previousApp.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.12)
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
                let window, CFGetTypeID(window) == AXUIElementGetTypeID()
            {
                previousWindow = unsafeDowncast(window, to: AXUIElement.self)
            }
        }
    }
}

extension QuickPanelController {
    func installBackground() {
        let hosting = NSHostingView(rootView: QuickPanelPascalSkin(controller: self))
        hosting.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        if configuration.glass, !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let glass = NSVisualEffectView(frame: panel.contentView?.bounds ?? panel.frame)
            glass.material = .hudWindow
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.appearance = NSAppearance(named: .darkAqua)
            let tint = NSView(frame: glass.bounds)
            tint.wantsLayer = true
            let tintColor = NSColor(srgbRed: 8 / 255, green: 27 / 255, blue: 64 / 255, alpha: 0.48)
            tint.layer?.backgroundColor = tintColor.cgColor
            tint.autoresizingMask = [.width, .height]
            glass.addSubview(tint)
            hosting.frame = glass.bounds
            glass.addSubview(hosting)
            panel.contentView = glass
        } else {
            let background = NSView(frame: panel.contentView?.bounds ?? panel.frame)
            background.wantsLayer = true
            background.layer?.backgroundColor =
                NSColor(
                    srgbRed: 13 / 255, green: 32 / 255, blue: 59 / 255, alpha: 1
                ).cgColor
            hosting.frame = background.bounds
            hosting.autoresizingMask = [.width, .height]
            background.addSubview(hosting)
            panel.contentView = background
        }
    }
}
