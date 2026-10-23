import Foundation

/// User-facing caret feel. Values are this project's own tuning:
/// "Glide" is a Monkeytype-style smooth caret, "Comet" a Neovide-style stretching trail.
public enum CaretPreset: String, CaseIterable, Identifiable, Codable {
    case off, glide, trail, comet, railgun, pixiedust

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return "Off (native caret)"
        case .glide: return "Glide"
        case .trail: return "Trail"
        case .comet: return "Comet"
        case .railgun: return "Railgun"
        case .pixiedust: return "Pixiedust"
        }
    }

    public var detail: String {
        switch self {
        case .off: return "The system text cursor, unchanged."
        case .glide: return "The whole caret slides smoothly between characters."
        case .trail: return "Short trail when you jump, quick glide when you type."
        case .comet: return "Long stretching trail on jumps, like a fast editor cursor."
        case .railgun: return "A quick caret with a fading particle beam on jumps."
        case .pixiedust: return "A soft scatter of fading sparks as you type."
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
