import AppKit
import SwiftUI

/// The Quick Panel's own visual system: a Turbo Pascal-style IDE over the desktop. It is deliberately
/// separate from the main window's Luuna tokens (owner decision, 2026-11-26: keep the Pascal panel style),
/// so every panel view reads its colours, type and pane chrome from here instead of literals.
enum PascalInk {
    /// An sRGB colour from 0–255 channels, the way the palette was specified.
    private static func rgb(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: alpha)
    }

    // Grounds, back to front.
    static let overlay = rgb(9, 35, 74, 0.36)
    static let band = rgb(66, 98, 125, 0.45)
    static let pane = rgb(6, 23, 47, 0.2)
    static let header = rgb(10, 36, 68, 0.8)
    static let titleBox = rgb(16, 37, 65, 0.98)
    static let selection = rgb(56, 186, 208, 0.36)
    /// The scrim behind a modal overlay (the ⌘K palette).
    static let scrim = Color.black.opacity(0.25)

    // Pane rules: the focused pane's double rule is bright, the rest are quiet.
    static let activeRule = rgb(180, 235, 241, 0.95)
    static let idleRule = rgb(129, 161, 183, 0.65)

    // Text.
    static let primary = rgb(224, 237, 244)
    static let footer = rgb(216, 234, 240)
    static let meta = rgb(139, 179, 198)
    static let title = rgb(243, 221, 150)
    static let inactiveTitle = rgb(198, 228, 237)

    // Signals: cyan for state and headings, gold for keys, coral for attention, notice for warnings.
    static let cyan = rgb(120, 224, 230)
    static let gold = rgb(243, 206, 131)
    static let coral = rgb(255, 169, 154)
    static let notice = rgb(244, 205, 129)
}

/// The panel typeface: the bundled VGA face by default, any installed font by name, falling back to the
/// system monospaced font.
enum PascalType {
    static func name(_ preferred: String) -> String {
        preferred == "VGA" ? (BundledFonts.vgaName ?? preferred) : preferred
    }

    static func font(_ size: CGFloat, preferred: String) -> Font {
        let selected = name(preferred)
        if NSFont(name: selected, size: size) != nil {
            return .custom(selected, size: size, relativeTo: .body)
        }
        return .system(size: size, design: .monospaced)
    }

    /// The panel's base size: body text, pane titles and table rows.
    static let baseSize: CGFloat = 13
}

/// Pane, row and band geometry shared by every panel page.
enum PascalMetrics {
    /// The top stats bar and the bottom footer band.
    static let bandHeight: CGFloat = 29
    /// One table, list or process row.
    static let rowHeight: CGFloat = 28
    /// A pinned table header.
    static let headerHeight: CGFloat = 27
    /// Content inset inside a pane's double rule.
    static let paneInsets = EdgeInsets(top: 18, leading: 9, bottom: 15, trailing: 9)
    /// The inner rule's distance from the pane edge.
    static let innerRuleInset: CGFloat = 3.5
    /// How far the pane title sits above the top rule, so the rule runs through it.
    static let titleLift: CGFloat = 7
}

/// One IDE window: a translucent ground inside a double rule, its title boxed into the top rule. The active
/// pane's rule and title are bright; inactive ones are quiet. The title is the pane's accessible heading.
struct PascalPane<Content: View>: View {
    let title: String
    let active: Bool
    @ViewBuilder var content: Content

    init(_ title: String, active: Bool, @ViewBuilder content: () -> Content) {
        self.title = title
        self.active = active
        self.content = content()
    }

    var body: some View {
        let rule = active ? PascalInk.activeRule : PascalInk.idleRule
        ZStack(alignment: .top) {
            PascalInk.pane
            content.padding(PascalMetrics.paneInsets)
        }
        .overlay {
            Rectangle().strokeBorder(rule, lineWidth: 1).padding(0.5)
            Rectangle().strokeBorder(rule, lineWidth: 1).padding(PascalMetrics.innerRuleInset)
        }
        .overlay(alignment: .top) {
            Text(" \(title) ")
                .panelFont(PascalType.baseSize)
                .foregroundStyle(active ? PascalInk.title : PascalInk.inactiveTitle)
                .padding(.horizontal, 3)
                .background(PascalInk.titleBox)
                .offset(y: -PascalMetrics.titleLift)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension View {
    /// The selected-row band. `focused: false` dims it for a list whose pane is not focused.
    func pascalSelection(_ selected: Bool, focused: Bool = true) -> some View {
        background(selected ? (focused ? PascalInk.selection : PascalInk.selection.opacity(0.35)) : .clear)
    }
}
