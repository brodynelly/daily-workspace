import SwiftUI

/// One screen in the sidebar (Mantine NavLink metrics: 8 × 12 pt padding, 12 pt gap, 8 pt radius). The
/// current screen shows by accent text and semibold weight, never by a filled pill; hover is a fill.
struct NavItem: View {
    let title: String
    let symbol: String
    let current: Bool
    var shortcut: String?
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: current ? .semibold : .regular))
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                    .foregroundStyle(current ? Theme.accentText : Theme.inkMuted)
                Text(title)
                    .font(.system(size: TextRole.label.size, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? Theme.accentText : hovered ? Theme.ink : Theme.inkBody)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .surface(hovered && !current ? Theme.fill : .clear)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// One live state in words, led by its tone's mark (the sidebar footer's status line). Nothing pulses.
struct StatusLine: View {
    let tone: Tone
    let label: String
    var detail: String?

    var body: some View {
        HStack(spacing: Space.s2) {
            ToneMark(tone: tone)
            Text(label).textRole(.caption, lineBox: false).foregroundStyle(Theme.inkBody).lineLimit(1)
        }
        .help(detail ?? label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// The 56 pt top bar above the content column: 32 pt side padding and a bottom hairline.
struct TopBar<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        HStack(spacing: Space.s2) { content }
            .padding(.horizontal, Space.s8)
            .frame(height: Metrics.topBarHeight)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
            .overlay(alignment: .bottom) { Hairline() }
    }
}

/// The "Go to…" trigger shaped as a search field: it opens the command palette.
struct PaletteTrigger: View {
    var title = "Go to…"
    let keys: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass").iconRole(.inline).accessibilityHidden(true)
                Text(title).textRole(.body, lineBox: false)
                Spacer(minLength: Space.s2)
                Kbd(keys)
            }
            .foregroundStyle(hovered ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, Space.s3)
            .frame(height: Metrics.controlMd)
            .frame(maxWidth: Metrics.paletteTriggerMaxWidth)
            .surface(hovered ? Theme.fillStrong : Theme.fill)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Go to a screen or run a command (\(keys))")
        .accessibilityLabel("Go to a screen or run a command")
    }
}
