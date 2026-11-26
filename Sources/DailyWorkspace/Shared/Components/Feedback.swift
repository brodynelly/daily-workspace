import SwiftUI

/// A toned box (Mantine Alert) for outages, open questions and a source's activity: the tone's soft ground
/// with its shape mark at the lead and body ink. Untoned, it is a muted note on the muted surface.
struct Callout<Content: View>: View {
    var tone: Tone?
    @ViewBuilder var content: Content

    init(tone: Tone? = nil, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            if let tone {
                ToneMark(tone: tone).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            VStack(alignment: .leading, spacing: Space.s2) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textRole(.bodySmall, lineBox: false)
        .foregroundStyle(tone == nil ? Theme.inkMuted : Theme.inkBody)
        .padding(Space.s4)
        .surface(tone?.background ?? Theme.surfaceMuted)
        .accessibilityElement(children: .combine)
    }
}

extension Callout where Content == Text {
    init(_ text: String, tone: Tone? = nil) {
        self.init(tone: tone) { Text(text) }
    }
}

/// A recorded reason in the tone of the state it explains: a 3 pt tone rule, the tone's mark, and the
/// reason in the tone's colour. With `next`, the next allowed step follows flush under it.
struct ReasonNote: View {
    let reason: String
    let tone: Tone
    var next: String?

    init(_ reason: String, tone: Tone, next: String? = nil) {
        self.reason = reason
        self.tone = tone
        self.next = next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s1Half) {
                ToneMark(tone: tone).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(reason).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(tone.foreground)
            .ruled(tone.markColor)
            if let next { NextStepNote(next) }
        }
        .textRole(.bodySmall, lineBox: false)
    }
}

/// The next allowed step, on its own line, ruled in the accent: the accent means Brody acts.
struct NextStepNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .textRole(.bodySmall, lineBox: false)
            .foregroundStyle(Theme.inkBody)
            .fixedSize(horizontal: false, vertical: true)
            .ruled(Theme.accent)
            .accessibilityLabel(Text("Next step: \(text)"))
    }
}

extension View {
    /// A 3 pt leading rule with the content inset 8 pt from it.
    fileprivate func ruled(_ color: Color) -> some View {
        padding(.leading, Space.s2)
            .overlay(alignment: .leading) {
                Rectangle().fill(color).frame(width: Metrics.ruleWidth).accessibilityHidden(true)
            }
    }
}

/// An empty screen or list says what is missing as a plain fact, then offers the control that adds it, only
/// where that control already exists. An optional glyph is decorative. `boxed` draws the dashed box.
struct EmptyState<Action: View>: View {
    let title: String
    var description: String?
    var systemImage: String?
    var boxed = false
    @ViewBuilder var action: Action

    init(
        _ title: String, description: String? = nil, systemImage: String? = nil, boxed: Bool = false,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.boxed = boxed
        self.action = action()
    }

    var body: some View {
        VStack(spacing: Space.s1Half) {
            if let systemImage {
                Image(systemName: systemImage)
                    .iconRole(.emptyState)
                    .foregroundStyle(Theme.inkDisabled)
                    .padding(.bottom, Space.s2)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textRole(.label, lineBox: false)
                .foregroundStyle(Theme.ink)
            if let description {
                Text(description)
                    .textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: Metrics.emptyDescriptionMax)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action.padding(.top, Space.s3)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, boxed ? Space.s6 : Space.s4)
        .padding(.horizontal, boxed ? Space.s6 : 0)
        .overlay {
            if boxed {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: Metrics.borderWidth, dash: [4, 3]))
            }
        }
    }
}

extension EmptyState where Action == EmptyView {
    init(_ title: String, description: String? = nil, systemImage: String? = nil, boxed: Bool = false) {
        self.init(title, description: description, systemImage: systemImage, boxed: boxed) { EmptyView() }
    }
}
