import DailyCore

/// User-facing names for caret presets. Kept in the app so DailyCore stays free of UI copy.
extension CaretPreset {
    var title: String {
        switch self {
        case .off: return "Off (native caret)"
        case .glide: return "Glide"
        case .trail: return "Trail"
        case .comet: return "Comet"
        case .railgun: return "Railgun"
        case .pixiedust: return "Pixiedust"
        }
    }

    var detail: String {
        switch self {
        case .off: return "The system text cursor, unchanged."
        case .glide: return "The whole caret slides smoothly between characters."
        case .trail: return "Short trail when you jump, quick glide when you type."
        case .comet: return "Long stretching trail on jumps, like a fast editor cursor."
        case .railgun: return "A quick caret with a fading particle beam on jumps."
        case .pixiedust: return "A soft scatter of fading sparks as you type."
        }
    }
}
