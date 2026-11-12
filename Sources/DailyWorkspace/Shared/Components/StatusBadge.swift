import SwiftUI

/// The one status chip: the source's own status text, verbatim, on the tone's soft ground with its shape
/// mark. Never transforms case and never adds words. Untoned, it is a plain chip on the strong fill.
/// It never animates.
struct StatusBadge: View {
    let text: String
    var tone: Tone?

    init(_ text: String, tone: Tone?) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: Space.s1Half) {
            if let tone { ToneMark(tone: tone) }
            Text(verbatim: text)
                .font(.system(size: TextRole.caption.size, weight: .bold))
                .monospacedDigit()
                .textCase(nil)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(tone?.foreground ?? Theme.inkBody)
        .padding(.horizontal, Space.s2Half)
        .frame(minHeight: Metrics.badgeHeight)
        .background(Capsule().fill(tone?.background ?? Theme.fillStrong))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}

/// A static descriptor chip ("project:alpha", "Org", "read-only"): outlined and untoned.
struct Tag: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: TextRole.caption.size, weight: .bold))
            .textCase(nil)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.inkBody)
            .padding(.horizontal, Space.s2Half)
            .frame(minHeight: Metrics.badgeHeight)
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Metrics.borderWidth))
    }
}

/// A key cap (Mantine Kbd): 12 pt mono bold on the muted ground, a separator edge with a heavier bottom.
struct Kbd: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(verbatim: keys)
            .font(.system(size: TextRole.caption.size, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, Space.s1Half)
            .padding(.top, Space.sHalf)
            .padding(.bottom, Space.sHalf + 2)
            .frame(minWidth: Metrics.kbdSize, minHeight: Metrics.kbdSize)
            .background {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Theme.separator)
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Theme.surfaceMuted)
                        .padding(EdgeInsets(top: 1, leading: 1, bottom: 3, trailing: 1))
                }
            }
            .fixedSize()
            .accessibilityLabel(Text(verbatim: keys))
    }
}
