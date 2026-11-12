import SwiftUI

/// How a `RecordList` draws its records.
enum RecordListVariant: Sendable {
    /// Compact hairline rows: no card chrome, a 40 pt row rhythm and a hover tint.
    case rows
    /// Bordered cards 8 pt apart. Static: no hover unless the record is actionable.
    case cards
}

private struct RecordListVariantKey: EnvironmentKey {
    static let defaultValue = RecordListVariant.cards
}

extension EnvironmentValues {
    var recordListVariant: RecordListVariant {
        get { self[RecordListVariantKey.self] }
        set { self[RecordListVariantKey.self] = newValue }
    }
}

/// A list of records (open loops, projects, events). Status lives in each record's own badge, never in an
/// edge colour.
struct RecordList<Content: View>: View {
    var variant: RecordListVariant = .cards
    @ViewBuilder var content: Content

    init(variant: RecordListVariant = .cards, @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.content = content()
    }

    var body: some View {
        switch variant {
        case .rows:
            // Each row draws a top hairline; the first one is clipped away, so lines fall only between rows.
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.top, -Metrics.borderWidth)
                .clipped()
                .environment(\.recordListVariant, .rows)
        case .cards:
            VStack(alignment: .leading, spacing: Space.s2) { content }
                .environment(\.recordListVariant, .cards)
        }
    }
}

/// One record. Free-form content, or the standard layout through
/// `RecordRow(title:meta:action:leading:trailing:)`. With an action the whole record is a button.
struct RecordRow<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    @Environment(\.recordListVariant) private var variant
    @State private var hovered = false

    init(action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { chrome }.buttonStyle(.plain)
            } else {
                chrome
            }
        }
        .onHover { hovered = $0 }
    }

    private var chrome: some View {
        let rows = variant == .rows
        let tint = hovered && (rows || action != nil)
        return VStack(alignment: .leading, spacing: Space.s1Half) { content }
            .textRole(.bodySmall, lineBox: false)
            .foregroundStyle(Theme.inkBody)
            .monospacedDigit()
            .padding(.horizontal, Space.s3)
            .padding(.vertical, rows ? Space.s2 : Space.s3)
            .frame(maxWidth: .infinity, minHeight: rows ? Metrics.rowHeight : nil, alignment: .leading)
            .background {
                if rows {
                    Rectangle().fill(tint ? Theme.fill : .clear)
                } else {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(tint ? Theme.fill : .clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Theme.separator, lineWidth: Metrics.borderWidth)
                        }
                }
            }
            .overlay(alignment: .top) { if rows { Hairline() } }
            .contentShape(Rectangle())
    }
}

/// The standard record layout: an optional leading badge, a title with a muted meta line under it, and
/// trailing badges or actions.
struct RecordRowLayout<Leading: View, Trailing: View>: View {
    let title: String
    var meta: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            leading
            VStack(alignment: .leading, spacing: Space.sHalf) {
                Text(title)
                    .textRole(.body, lineBox: false)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta {
                    Text(meta)
                        .textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s2) { trailing }
        }
    }
}

extension RecordRow {
    init<Leading: View, Trailing: View>(
        title: String, meta: String? = nil, action: (() -> Void)? = nil,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) where Content == RecordRowLayout<Leading, Trailing> {
        self.init(action: action) {
            RecordRowLayout(title: title, meta: meta, leading: leading, trailing: trailing)
        }
    }

    init<Trailing: View>(
        title: String, meta: String? = nil, action: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing
    ) where Content == RecordRowLayout<EmptyView, Trailing> {
        self.init(title: title, meta: meta, action: action, leading: { EmptyView() }, trailing: trailing)
    }

    init(title: String, meta: String? = nil, action: (() -> Void)? = nil)
    where Content == RecordRowLayout<EmptyView, EmptyView> {
        self.init(title: title, meta: meta, action: action, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}
