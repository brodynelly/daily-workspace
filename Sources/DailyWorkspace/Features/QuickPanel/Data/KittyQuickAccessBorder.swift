import AppKit
import ApplicationServices
import Darwin

/// The WindowServer's bounds identify QAT's AXUnknown window without requesting screen pixels.
struct KittyQuickAccessWindow {
    let ownerPID: pid_t
    let bounds: CGRect
    let layer: Int
    let alpha: Double

    static func target(in windows: [Self], frontmostPID: pid_t) -> Self? {
        windows.first {
            $0.ownerPID == frontmostPID && $0.alpha > 0 && $0.bounds.width > 80 && $0.bounds.height > 60
        }
    }
}

@MainActor
private final class KittyBorderView: NSView {
    var strokeColor = NSColor(srgbRed: 0x37 / 255, green: 0xf4 / 255, blue: 0x99 / 255, alpha: 1) {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        strokeColor.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        path.stroke()
    }
}

private let kittyAXCallback: AXObserverCallback = { _, _, _, context in
    guard let context else { return }
    let tracker = Unmanaged<KittyQuickAccessBorder>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { [weak tracker] in
        MainActor.assumeIsolated { tracker?.updateBorder() }
    }
}

@MainActor
final class KittyQuickAccessBorder: QuickPanelBorderTracking {
    private static let bundleID = "net.kovidgoyal.kitty-quick-access"
    private let colorschemeURL: URL
    private let scheduler: any QuickPanelTimerScheduling
    private let frontmost: @MainActor () -> (bundleID: String?, pid: pid_t)?
    private var running = false
    private var observedPID: pid_t?
    private var axApp: AXUIElement?
    private var axObserver: AXObserver?
    private var fallback: (any QuickPanelTimerToken)?
    private let windows: @MainActor () -> [KittyQuickAccessWindow]
    private let accessibilityTrusted: () -> Bool
    private var paletteSource: DispatchSourceFileSystemObject?
    private var paletteFileSource: DispatchSourceFileSystemObject?
    private var panel: NSPanel?
    private var borderView: KittyBorderView?

    init(
        colorschemeURL: URL,
        scheduler: (any QuickPanelTimerScheduling)? = nil,
        frontmost: @escaping @MainActor () -> (bundleID: String?, pid: pid_t)? = {
            NSWorkspace.shared.frontmostApplication.map { ($0.bundleIdentifier, $0.processIdentifier) }
        },
        windows: @escaping @MainActor () -> [KittyQuickAccessWindow] = { KittyQuickAccessBorder.windowSnapshots() },
        accessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.colorschemeURL = colorschemeURL
        self.scheduler = scheduler ?? PanelTimerScheduler()
        self.frontmost = frontmost
        self.windows = windows
        self.accessibilityTrusted = accessibilityTrusted
    }

    func start() {
        guard !running else { return }
        running = true
        watchPalette()
        refresh()
    }

    func stop() {
        running = false
        fallback?.cancel()
        fallback = nil
        detachAXObserver()
        paletteSource?.cancel()
        paletteSource = nil
        paletteFileSource?.cancel()
        paletteFileSource = nil
        panel?.orderOut(nil)
    }

    func refresh() {
        guard running else { return }
        reloadColor()
        guard let front = frontmost(), front.bundleID == Self.bundleID else {
            fallback?.cancel()
            fallback = nil
            detachAXObserver()
            panel?.orderOut(nil)
            return
        }
        let pid = front.pid
        if observedPID != pid {
            fallback?.cancel()
            fallback = nil
            detachAXObserver()
            observedPID = pid
            attachAXObserver(to: pid)
            // QAT's AXUnknown windows sometimes omit movement notifications. Poll only while QAT is frontmost.
            fallback = scheduler.repeating(every: 0.25) { [weak self] in self?.updateBorder() }
        }
        updateBorder()
    }

    func updateBorder() {
        guard running, let front = frontmost(), front.bundleID == Self.bundleID,
            front.pid == observedPID
        else {
            refresh()
            return
        }
        guard let target = KittyQuickAccessWindow.target(in: windows(), frontmostPID: front.pid) else {
            panel?.orderOut(nil)
            return
        }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let bounds = target.bounds
        let frame = NSRect(
            x: bounds.minX - 2, y: desktopTop - bounds.maxY - 2,
            width: bounds.width + 4, height: bounds.height + 4
        )
        if panel == nil {
            let newPanel = NSPanel(
                contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            newPanel.isReleasedWhenClosed = false
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.ignoresMouseEvents = true
            newPanel.hasShadow = false
            newPanel.hidesOnDeactivate = false
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            let view = KittyBorderView(frame: NSRect(origin: .zero, size: frame.size))
            newPanel.contentView = view
            borderView = view
            panel = newPanel
            reloadColor()
        }
        guard let panel else { return }
        panel.level = NSWindow.Level(rawValue: target.layer + 1)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func attachAXObserver(to pid: pid_t) {
        guard accessibilityTrusted() else { return }  // Do not request permission here; preserve the app's existing UX.
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var observer: AXObserver?
        guard AXObserverCreate(pid, kittyAXCallback, &observer) == .success, let observer else { return }
        axApp = app
        axObserver = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.commonModes)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, context)
        }
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        {
            let window = unsafeBitCast(focused, to: AXUIElement.self)
            for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                AXObserverAddNotification(observer, window, name as CFString, context)
            }
        }
    }

    private func detachAXObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), CFRunLoopMode.commonModes)
        }
        axObserver = nil
        axApp = nil
        observedPID = nil
    }

    private func watchPalette() {
        let folder = colorschemeURL.deletingLastPathComponent().path
        let fd = Darwin.open((folder as NSString).fileSystemRepresentation, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.reloadColor()
                // An atomic replacement changes the file inode; watch the new one.
                self.watchPaletteFile()
            }
        }
        source.setCancelHandler { _ = Darwin.close(fd) }
        paletteSource = source
        source.resume()
        watchPaletteFile()
    }

    private func watchPaletteFile() {
        paletteFileSource?.cancel()
        paletteFileSource = nil
        let fd = Darwin.open(colorschemeURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.reloadColor()
                if let events = self.paletteFileSource?.data, !events.isDisjoint(with: [.rename, .delete]) {
                    self.watchPaletteFile()
                }
            }
        }
        source.setCancelHandler { _ = Darwin.close(fd) }
        paletteFileSource = source
        source.resume()
    }

    private func reloadColor() {
        let color = Self.color(in: (try? String(contentsOf: colorschemeURL, encoding: .utf8)) ?? "")
        borderView?.strokeColor = color
    }

    static func color(in contents: String) -> NSColor {
        let fallback = NSColor(srgbRed: 0x37 / 255, green: 0xf4 / 255, blue: 0x99 / 255, alpha: 1)
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?m)^[ \t]*bnelly_color02=["']?(#[0-9a-fA-F]{6})["']?[ \t]*$"#
            ), let match = regex.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)),
            let range = Range(match.range(at: 1), in: contents),
            let rgb = UInt32(contents[range].dropFirst(), radix: 16)
        else { return fallback }
        return NSColor(
            srgbRed: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: 1
        )
    }

    private static func windowSnapshots() -> [KittyQuickAccessWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let records = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return records.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
                let rect = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: rect as CFDictionary),
                let alpha = info[kCGWindowAlpha as String] as? NSNumber,
                let layer = info[kCGWindowLayer as String] as? NSNumber
            else { return nil }
            return KittyQuickAccessWindow(
                ownerPID: pid.int32Value, bounds: bounds, layer: layer.intValue, alpha: alpha.doubleValue
            )
        }
    }
}
