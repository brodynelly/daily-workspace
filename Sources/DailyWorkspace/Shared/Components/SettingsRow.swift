import SwiftUI

/// A titled setting (Ledger SettingsRow): the title with an optional badge, a muted description, and a
/// trailing control. Rows are separated by hairlines; pass `divider: false` on the last one. `stacked` puts
/// the control under the text. The title is not a heading.
struct SettingsRow<Badge: View, Control: View>: View {
    let title: String
    var description: String?
    var stacked = false
    var divider = true
    @ViewBuilder var badge: Badge
    @ViewBuilder var control: Control

    init(
        _ title: String, description: String? = nil, stacked: Bool = false, divider: Bool = true,
        @ViewBuilder badge: () -> Badge, @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.stacked = stacked
        self.divider = divider
        self.badge = badge()
        self.control = control()
    }

    var body: some View {
        let layout =
            stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s3))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.s6))
        layout {
            VStack(alignment: .leading, spacing: Space.sHalf) {
                HStack(spacing: Space.s2) {
                    Text(title).textRole(.bodyStrong, lineBox: false).foregroundStyle(Theme.ink)
                    badge
                }
                if let description {
                    Text(description)
                        .textRole(.body, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s2) { control }.fixedSize()
        }
        .padding(.vertical, Space.s4)
        .overlay(alignment: .bottom) { if divider { Hairline() } }
        .accessibilityElement(children: .contain)
    }
}

extension SettingsRow where Badge == EmptyView {
    init(
        _ title: String, description: String? = nil, stacked: Bool = false, divider: Bool = true,
        @ViewBuilder control: () -> Control
    ) {
        self.init(
            title, description: description, stacked: stacked, divider: divider, badge: { EmptyView() },
            control: control)
    }
}
