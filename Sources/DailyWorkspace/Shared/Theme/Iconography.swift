import SwiftUI

/// SF Symbol sizes, matched to the text they sit beside so a glyph never outweighs its label
/// (HIG `sf-symbols.md`: match the symbol's weight and size to adjacent text).
enum IconRole: CaseIterable {
    /// 10 pt semibold: disclosure chevrons beside 14 pt text.
    case disclosure
    /// 11 pt: a glyph inside a caption or a citation line.
    case caption
    /// 13 pt: beside 14 pt labels, in buttons and at the lead of a field.
    case inline
    /// 15 pt: the only content of a 28 pt icon button.
    case control
    /// 16 pt: a row's or a heading's leading glyph (`Metrics.iconSize`).
    case leading
    /// 28 pt light: the decorative glyph of an empty state.
    case emptyState

    var size: CGFloat {
        switch self {
        case .disclosure: return 10
        case .caption: return 11
        case .inline: return 13
        case .control: return 15
        case .leading: return Metrics.iconSize
        case .emptyState: return 28
        }
    }

    var weight: Font.Weight {
        switch self {
        case .disclosure: return .semibold
        case .emptyState: return .light
        case .caption, .inline, .control, .leading: return .regular
        }
    }

    var font: Font { .system(size: size, weight: weight) }
}

extension View {
    /// Sizes an SF Symbol for its role.
    func iconRole(_ role: IconRole) -> some View { font(role.font) }
}
