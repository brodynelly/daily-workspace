import Foundation

public struct CaretPoint: Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct CaretRect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct CaretConfig: Equatable {
    /// Seconds for the slowest (trailing) corners on a long jump.
    public var animationLength: Double
    /// Seconds used when the caret moves a character or two on one line (typing).
    public var shortAnimationLength: Double
    /// 0 = every corner moves together (a glide); 1 = leading corners snap, trailing corners stretch behind.
    public var trailSize: Double
    /// A move of at most this many cell widths on the same line counts as typing.
    public var shortTravelCells: Double

    public init(animationLength: Double, shortAnimationLength: Double, trailSize: Double, shortTravelCells: Double = 2) {
        self.animationLength = animationLength
        self.shortAnimationLength = shortAnimationLength
        self.trailSize = trailSize
        self.shortTravelCells = shortTravelCells
    }
}

/// Four-corner caret in the style of Neovide: each corner has its own critically damped spring and its
/// own duration, chosen by how well the corner faces the direction of travel. Leading corners arrive
/// first, trailing corners lag, so the caret stretches into a trail on long jumps and glides on short ones.
public struct CaretAnimator {
    public var config: CaretConfig
    public private(set) var destination: CaretRect?

    private var springX = [CriticallyDampedSpring](repeating: .init(), count: 4)
    private var springY = [CriticallyDampedSpring](repeating: .init(), count: 4)
    private var lengths = [Double](repeating: 0.15, count: 4)

    // Corner order: top-left, top-right, bottom-right, bottom-left.
    private static let relative: [(x: Double, y: Double)] = [(0, 0), (1, 0), (1, 1), (0, 1)]

    public init(config: CaretConfig) {
        self.config = config
    }

    /// Corner positions right now.
    public var quad: [CaretPoint] {
        guard let d = destination else { return [] }
        return (0..<4).map { i in
            let rel = Self.relative[i]
            return CaretPoint(
                x: d.x + rel.x * d.width + springX[i].position,
                y: d.y + rel.y * d.height + springY[i].position
            )
        }
    }

    public var isAnimating: Bool {
        (0..<4).contains { !springX[$0].isSettled || !springY[$0].isSettled }
    }

    /// Point the caret at a new rectangle. `immediate` snaps without animating.
    public mutating func moveTo(_ rect: CaretRect, cellWidth: Double, immediate: Bool = false) {
        guard let old = destination else {
            destination = rect
            resetSprings()
            return
        }
        if immediate {
            destination = rect
            resetSprings()
            return
        }

        let dx = rect.x - old.x
        let dy = rect.y - old.y
        let moved = abs(dx) > 0.01 || abs(dy) > 0.01
        let resized = abs(rect.width - old.width) > 0.01 || abs(rect.height - old.height) > 0.01
        if !moved && !resized { return }

        let current = quad
        destination = rect
        for i in 0..<4 {
            let rel = Self.relative[i]
            let targetX = rect.x + rel.x * rect.width
            let targetY = rect.y + rel.y * rect.height
            springX[i].position = current[i].x - targetX
            springY[i].position = current[i].y - targetY
        }

        let distance = (dx * dx + dy * dy).squareRoot()
        let sameLine = abs(dy) < old.height * 0.5
        let isShort = sameLine && abs(dx) <= config.shortTravelCells * max(cellWidth, 1)
        let base = isShort ? min(config.animationLength, config.shortAnimationLength) : config.animationLength
        let trail = min(max(config.trailSize, 0), 1)
        let leading = base * (1 - trail)
        let trailing = base

        for i in 0..<4 {
            let rel = Self.relative[i]
            let cx = rel.x - 0.5
            let cy = rel.y - 0.5
            // 1 when the corner faces the direction of travel, −1 when it faces away.
            let alignment = distance > 0 ? (cx * dx + cy * dy) / (0.5.squareRoot() * distance) : 0
            let t = (min(max(alignment, -1), 1) + 1) / 2
            lengths[i] = trailing + (leading - trailing) * t
        }
    }

    /// Advance the spring simulation. Returns true while any corner is still moving.
    @discardableResult
    public mutating func step(dt: Double) -> Bool {
        for i in 0..<4 {
            springX[i].update(dt: dt, length: lengths[i])
            springY[i].update(dt: dt, length: lengths[i])
        }
        return isAnimating
    }

    private mutating func resetSprings() {
        for i in 0..<4 {
            springX[i] = .init()
            springY[i] = .init()
        }
    }
}
