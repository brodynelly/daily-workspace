import SwiftUI

/// A section heading row: the Outfit section title, then descriptor chips, badges or actions on the trailing
/// side, with an optional one-line description 8 pt under it.
struct SectionHeading<Accessory: View>: View {
    let title: String
    var description: String?
    @ViewBuilder var accessory: Accessory

    init(_ title: String, description: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.description = description
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(title)
                    .textRole(.sectionTitle, lineBox: false)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Space.s2) { accessory }
            }
            if let description {
                Text(description)
                    .textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: Metrics.measure, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SectionHeading where Accessory == EmptyView {
    init(_ title: String, description: String? = nil) {
        self.init(title, description: description) { EmptyView() }
    }
}

/// A titled section of a screen.
/// - `card`: a raised panel (16 pt padding, hairline, 8 pt radius, 16 pt gap). No hover, no dimming.
/// - `subpanel`: ruled off with a top hairline inside a card, 12 pt gap.
/// - `plain`: no chrome, 12 pt gap.
struct Panel<Accessory: View, Content: View>: View {
    enum Variant { case card, subpanel, plain }

    let title: String
    var description: String?
    var variant: Variant = .card
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(
        _ title: String, description: String? = nil, variant: Variant = .card,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.variant = variant
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: variant == .card ? Space.s4 : Space.s3) {
            SectionHeading(title, description: description) { accessory }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)

        switch variant {
        case .card:
            stack.padding(Space.s4).cardSurface()
        case .subpanel:
            stack.padding(.top, Space.s4).overlay(alignment: .top) { Hairline() }
        case .plain:
            stack
        }
    }
}

extension Panel where Accessory == EmptyView {
    init(
        _ title: String, description: String? = nil, variant: Variant = .card,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, description: description, variant: variant, accessory: { EmptyView() }, content: content)
    }
}

/// A muted group of related items inside a panel (and the stat tiles' tray).
struct Tray<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) { content }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.surfaceMuted))
    }
}

/// A 1 pt separator rule.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: Metrics.borderWidth).accessibilityHidden(true)
    }
}

/// A 1 pt vertical separator rule.
struct VerticalHairline: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(width: Metrics.borderWidth).accessibilityHidden(true)
    }
}
