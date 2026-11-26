import AppKit
import SwiftUI

/// Luuna's type roles (tokens-scale.css): size, line height and weight. Titles, headings and metrics use
/// Outfit at 600 (`BundledFonts`, falling back to the system font); body and UI text use the system font
/// (Mantine's `-apple-system` stack); identities use the system monospaced font. Tracking is 0 throughout.
enum TextRole: CaseIterable {
    /// Mantine h2: 26 / 1.35 / 600, Outfit. A screen's title.
    case pageTitle
    /// Mantine h4: 18 / 1.45 / 600, Outfit. A section or panel heading.
    case sectionTitle
    /// 20 / 1.4 / 600, Outfit. A stat tile's value.
    case metric
    /// 16 / 1 / 600, Outfit. The sidebar wordmark.
    case wordmark
    /// 16 / 1.55 / 600.
    case bodyStrong
    /// 16 / 1.55 / 400. The default text.
    case body
    /// 14 / 1.45 / 400: descriptions, meta lines, records and callouts.
    case bodySmall
    /// 14 / 1.45 / 600: labels, buttons and navigation.
    case label
    /// 12 / 1.4 / 400.
    case caption
    /// 12 / 1.4 / 600: sidebar section labels.
    case overline
    /// 14 / 1.55 / 400, monospaced: paths, ids and hashes.
    case mono
    /// 12 / 1.4 / 400, monospaced: short ids, tool arguments, diffs and file previews.
    case monoCaption

    enum Family { case display, text, mono }

    var size: CGFloat {
        switch self {
        case .pageTitle: return 26
        case .metric: return 20
        case .sectionTitle: return 18
        case .wordmark, .bodyStrong, .body: return 16
        case .bodySmall, .label, .mono: return 14
        case .caption, .overline, .monoCaption: return 12
        }
    }

    /// CSS line height as a multiple of the size.
    var lineHeight: CGFloat {
        switch self {
        case .pageTitle: return 1.35
        case .sectionTitle, .bodySmall, .label: return 1.45
        case .metric, .caption, .overline, .monoCaption: return 1.4
        case .wordmark: return 1
        case .bodyStrong, .body, .mono: return 1.55
        }
    }

    var weight: Font.Weight {
        switch self {
        case .pageTitle, .sectionTitle, .metric, .wordmark, .bodyStrong, .label, .overline: return .semibold
        case .body, .bodySmall, .caption, .mono, .monoCaption: return .regular
        }
    }

    var family: Family {
        switch self {
        case .pageTitle, .sectionTitle, .metric, .wordmark: return .display
        case .mono, .monoCaption: return .mono
        default: return .text
        }
    }

    /// The SwiftUI font for this role.
    var font: Font { Self.resolved[self]?.font ?? .system(size: size, weight: weight) }

    /// Extra space between lines so a line box is `size × lineHeight`, as in CSS.
    var leading: CGFloat { Self.resolved[self]?.leading ?? 0 }

    private struct Resolved {
        let font: Font
        let leading: CGFloat
    }

    /// Built once, after launch has registered the bundled fonts.
    private static let resolved: [TextRole: Resolved] = Dictionary(
        uniqueKeysWithValues: allCases.map { role in
            let nsFont = role.makeNSFont()
            let natural = nsFont.ascender - nsFont.descender + nsFont.leading
            return (
                role, Resolved(font: Font(nsFont as CTFont), leading: max(0, role.size * role.lineHeight - natural))
            )
        })

    private func makeNSFont() -> NSFont {
        let nsWeight: NSFont.Weight = weight == .semibold ? .semibold : .regular
        switch family {
        case .display: return BundledFonts.displayFont(size: size) ?? .systemFont(ofSize: size, weight: nsWeight)
        case .text: return .systemFont(ofSize: size, weight: nsWeight)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: nsWeight)
        }
    }
}

/// Applies a type role: font, CSS-like line height (half the extra leading above and below the box) and,
/// for display roles, nothing else: colour stays with the caller.
struct TextRoleModifier: ViewModifier {
    let role: TextRole
    var lineBox: Bool

    func body(content: Content) -> some View {
        content
            .font(role.font)
            .lineSpacing(role.leading)
            .padding(.vertical, lineBox ? role.leading / 2 : 0)
    }
}

extension View {
    /// Sets a Luuna type role. `lineBox: false` drops the half-leading padding for tight rows (badges, buttons).
    func textRole(_ role: TextRole, lineBox: Bool = true) -> some View {
        modifier(TextRoleModifier(role: role, lineBox: lineBox))
    }
}
