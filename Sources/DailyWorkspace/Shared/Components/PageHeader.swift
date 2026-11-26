import SwiftUI

/// One step of a breadcrumb trail. Ancestors with an action render as accent links; the last crumb is the
/// page itself.
struct Crumb: Identifiable {
    let id = UUID()
    let title: String
    var action: (() -> Void)?

    init(_ title: String, action: (() -> Void)? = nil) {
        self.title = title
        self.action = action
    }
}

/// The opening of a screen: a large Outfit title with its actions in the same row, then one sentence that
/// says what the screen is for. Optional breadcrumbs sit above the title (only where a real hierarchy
/// exists) and an optional meta line sits under the sentence. No card, no instructions.
struct PageHeader<Actions: View>: View {
    let title: String
    var description: String?
    var meta: String?
    var breadcrumbs: [Crumb] = []
    @ViewBuilder var actions: Actions

    init(
        title: String, description: String? = nil, meta: String? = nil, breadcrumbs: [Crumb] = [],
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.description = description
        self.meta = meta
        self.breadcrumbs = breadcrumbs
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sHalf) {
            if !breadcrumbs.isEmpty {
                Breadcrumbs(items: breadcrumbs).padding(.bottom, Space.s2 - Space.sHalf)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Space.s4) {
                    heading.fixedSize()
                    Spacer(minLength: 0)
                    HStack(spacing: Space.s2) { actions }.fixedSize()
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    heading
                    ChipFlow { actions }
                }
            }
            if let description {
                Text(description)
                    .textRole(.body)
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: Metrics.measure, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let meta {
                Text(meta)
                    .textRole(.bodySmall)
                    .foregroundStyle(Theme.inkMuted)
                    .monospacedDigit()
                    .padding(.top, Space.s1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var heading: some View {
        Text(title)
            .textRole(.pageTitle)
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

}

extension PageHeader where Actions == EmptyView {
    init(title: String, description: String? = nil, meta: String? = nil, breadcrumbs: [Crumb] = []) {
        self.init(title: title, description: description, meta: meta, breadcrumbs: breadcrumbs) { EmptyView() }
    }
}

/// Where a nested page sits: ancestors as accent links separated by "/", the current page in ink.
struct Breadcrumbs: View {
    let items: [Crumb]

    var body: some View {
        HStack(spacing: Space.s2Half) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 { Text(verbatim: "/").foregroundStyle(Theme.inkMuted).accessibilityHidden(true) }
                if index == items.count - 1 || crumb.action == nil {
                    Text(crumb.title).foregroundStyle(index == items.count - 1 ? Theme.ink : Theme.inkBody)
                } else if let action = crumb.action {
                    Button(crumb.title, action: action).buttonStyle(.plain).foregroundStyle(Theme.accentText)
                }
            }
        }
        .textRole(.body, lineBox: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Breadcrumb")
    }
}

/// The content column of one screen: Luuna's page padding (20 top, 32 sides and bottom), left-aligned,
/// capped at the 1200 pt content width, with 20 pt between the header and each block.
/// `scrolls: false` is for screens that manage their own scrolling (the editor, the Assistant): the
/// column then fills the height.
struct Page<Content: View>: View {
    var scrolls = true
    @ViewBuilder var content: Content

    init(scrolls: Bool = true, @ViewBuilder content: () -> Content) {
        self.scrolls = scrolls
        self.content = content()
    }

    var body: some View {
        if scrolls {
            ScrollView {
                column.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            column
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Space.s5) { content }
            .padding(Metrics.pagePadding)
            .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
    }
}
