import Foundation

/// Caret feel. Values are this project's own tuning: "Glide" is a Monkeytype-style smooth caret,
/// "Comet" a Neovide-style stretching trail. User-facing names live in the app target.
public enum CaretPreset: String, CaseIterable, Identifiable, Codable {
    case off, glide, trail, comet, railgun, pixiedust

    public var id: String { rawValue }

    /// Extra visual drawn by the overlay on top of the caret motion.
    public var effect: CaretEffect {
        switch self {
        case .railgun: return .beam
        case .pixiedust: return .sparks
        case .off, .glide, .trail, .comet: return .none
        }
    }

    public var config: CaretConfig {
        switch self {
        case .off: return CaretConfig(animationLength: 0, shortAnimationLength: 0, trailSize: 0)
        case .glide: return CaretConfig(animationLength: 0.14, shortAnimationLength: 0.09, trailSize: 0)
        case .trail: return CaretConfig(animationLength: 0.15, shortAnimationLength: 0.07, trailSize: 0.5)
        case .railgun, .pixiedust: return CaretConfig(animationLength: 0.16, shortAnimationLength: 0.08, trailSize: 0.5)
        case .comet: return CaretConfig(animationLength: 0.22, shortAnimationLength: 0.10, trailSize: 0.85)
        }
    }
}

/// Particle effect layered on caret jumps.
public enum CaretEffect: Equatable, Sendable {
    case none
    /// A fading straight beam from the old to the new position.
    case beam
    /// Scattered fading sparks along the path.
    case sparks
}
