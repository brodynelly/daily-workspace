import AppKit
import DailyCore

/// Transparent overlay that draws the animated caret quad. It never takes clicks.
final class CaretOverlayView: NSView {
    var quad: [CaretPoint] = [] {
        didSet { needsDisplay = true }
    }

    struct Particle {
        var point: CGPoint
        var velocity: CGVector
        var life: Double = 0.45
    }
    var particles: [Particle] = []

    func emit(from start: CGPoint, to end: CGPoint, beam: Bool) {
        let count = beam ? 20 : 8
        for i in 0..<count {
            let t = beam ? CGFloat(i) / CGFloat(count) : 1
            particles.append(Particle(point: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), velocity: CGVector(dx: CGFloat.random(in: -25...25), dy: CGFloat.random(in: -35...35))))
        }
        particles = Array(particles.suffix(160))
    }

    func stepParticles(_ dt: Double) {
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].point.x += particles[i].velocity.dx * dt
            particles[i].point.y += particles[i].velocity.dy * dt
        }
        particles.removeAll { $0.life <= 0 }
        needsDisplay = true
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        for particle in particles {
            WorkspaceTheme.nativeAccent.withAlphaComponent(max(0, particle.life / 0.45)).setFill()
            NSBezierPath(ovalIn: CGRect(x: particle.point.x, y: particle.point.y, width: 2, height: 2)).fill()
        }
        guard quad.count == 4 else { return }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: quad[0].x, y: quad[0].y))
        for p in quad.dropFirst() { path.line(to: NSPoint(x: p.x, y: p.y)) }
        path.close()
        WorkspaceTheme.nativeAccent.setFill()
        path.fill()
    }

    override func accessibilityRole() -> NSAccessibility.Role? { nil }
    override func isAccessibilityElement() -> Bool { false }
}

/// NSTextView whose insertion point is replaced by a spring-animated caret.
///
/// Falls back to the native system caret whenever the animated one could hurt input:
/// the preset is Off, macOS Reduce Motion is on, an IME has marked text, or a range is selected.
final class CaretTextView: NSTextView {
    var caretPreset: CaretPreset = .glide {
        didSet { if oldValue != caretPreset { presetChanged() } }
    }
    var systemReduceMotion = false {
        didSet { if oldValue != systemReduceMotion { presetChanged() } }
    }

    private let overlay = CaretOverlayView()
    private var animator = CaretAnimator(config: CaretPreset.glide.config)
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var blinkTimer: Timer?
    private var idleWork: DispatchWorkItem?
    private var overlayWasHidden = true
    private var isRetargeting = false
    private let caretWidth: CGFloat = 2

    private var smoothActive: Bool { caretPreset != .off && !systemReduceMotion }

    func installOverlay() {
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        addSubview(overlay, positioned: .above, relativeTo: nil)
        animator.config = caretPreset.config
    }

    deinit {
        link?.invalidate()
        blinkTimer?.invalidate()
    }

    // MARK: Hooks

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        retargetCaret()
        DispatchQueue.main.async { [weak self] in self?.retargetCaret() }
    }

    override func didChangeText() {
        super.didChangeText()
        retargetCaret()
        DispatchQueue.main.async { [weak self] in self?.retargetCaret() }
    }

    override func layout() {
        super.layout()
        retargetCaret()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        retargetCaret(snap: true)
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        hideOverlay()
        return ok
    }

    override func unmarkText() {
        super.unmarkText()
        retargetCaret()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        retargetCaret()
    }

    // MARK: Caret

    private func presetChanged() {
        animator.config = caretPreset.config
        retargetCaret(snap: true)
    }

    private func caretRect() -> CGRect? {
        guard let window else { return nil }
        let location = selectedRange().location
        let screen = firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        guard screen.height > 1 else { return nil }
        var rect = convert(window.convertFromScreen(screen), from: nil)
        rect.size.width = caretWidth
        return rect
    }

    func retargetCaret(snap: Bool = false) {
        guard !isRetargeting else { return }
        isRetargeting = true
        defer { isRetargeting = false }

        let canAnimate = smoothActive
            && window?.firstResponder === self
            && !hasMarkedText()
            && selectedRange().length == 0

        guard canAnimate, let rect = caretRect() else {
            hideOverlay()
            return
        }

        setNativeCaret(visible: false)
        overlay.isHidden = false

        let cell = max(Double(font?.maximumAdvancement.width ?? 8), 1)
        let target = CaretRect(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
        if !snap && !overlayWasHidden, let previous = animator.destination,
           abs(previous.x - target.x) + abs(previous.y - target.y) > 1,
           caretPreset == .railgun || caretPreset == .pixiedust {
            overlay.emit(from: CGPoint(x: previous.x, y: previous.y + previous.height / 2), to: CGPoint(x: target.x, y: target.y + target.height / 2), beam: caretPreset == .railgun)
        }
        animator.moveTo(target, cellWidth: cell, immediate: snap || overlayWasHidden)
        overlayWasHidden = false
        overlay.quad = animator.quad

        restartIdleBlink()
        if animator.isAnimating || !overlay.particles.isEmpty { startLink() }
    }

    private func hideOverlay() {
        overlay.isHidden = true
        overlay.particles = []
        overlayWasHidden = true
        stopLink()
        blinkTimer?.invalidate()
        idleWork?.cancel()
        setNativeCaret(visible: true)
    }

    /// Hide or restore the system caret. macOS 14+ draws it with NSTextInsertionIndicator.
    private func setNativeCaret(visible: Bool) {
        insertionPointColor = visible ? .labelColor : .clear
        func walk(_ view: NSView) {
            for sub in view.subviews {
                if let indicator = sub as? NSTextInsertionIndicator {
                    indicator.displayMode = visible ? .automatic : .hidden
                } else if sub !== overlay {
                    walk(sub)
                }
            }
        }
        walk(self)
    }

    // MARK: Animation loop

    private func startLink() {
        guard link == nil else { return }
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        lastTimestamp = 0
        link = l
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ l: CADisplayLink) {
        let raw = lastTimestamp == 0 ? l.duration : l.timestamp - lastTimestamp
        lastTimestamp = l.timestamp
        let dt = min(max(raw, 0.001), 0.05)
        let moving = animator.step(dt: dt)
        overlay.quad = animator.quad
        overlay.stepParticles(dt)
        if !moving && overlay.particles.isEmpty { stopLink() }
    }

    // MARK: Blink (solid while typing, blinks when idle)

    private func restartIdleBlink() {
        blinkTimer?.invalidate()
        overlay.alphaValue = 1
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
                guard let overlay = self?.overlay else { return }
                overlay.alphaValue = overlay.alphaValue > 0.5 ? 0 : 1
            }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
