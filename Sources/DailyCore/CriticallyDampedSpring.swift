import Foundation

/// One-dimensional critically damped spring using the exact closed-form solution,
/// so it is stable for any frame time. `position` is the remaining offset from the target.
///
/// x(t) = (a + b·t)·e^(−ω·t), with a = x0 and b = v0 + ω·x0.
/// ω = 6 / length makes the offset fall below ~1.7 % of its start after `length` seconds.
/// (That constant is this project's own tuning, not copied from Neovide.)
public struct CriticallyDampedSpring: Equatable {
    public var position: Double
    public var velocity: Double

    public init(position: Double = 0, velocity: Double = 0) {
        self.position = position
        self.velocity = velocity
    }

    public var isSettled: Bool { position == 0 && velocity == 0 }

    public mutating func update(dt: Double, length: Double) {
        if length <= dt || length <= 0 {
            position = 0
            velocity = 0
            return
        }
        let omega = 6.0 / length
        let a = position
        let b = position * omega + velocity
        let c = exp(-omega * dt)
        position = (a + b * dt) * c
        velocity = c * (-a * omega - b * dt * omega + b)
        if abs(position) < 0.02 && abs(velocity) < 0.5 {
            position = 0
            velocity = 0
        }
    }
}
