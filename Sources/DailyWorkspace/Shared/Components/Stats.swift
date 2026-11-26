import SwiftUI

/// A short row of counts (Ledger MetricCard) on a muted tray: four across, two by two when narrow. A count is
/// a projection of records, not evidence, so tiles are never toned. Numerals are tabular.
struct StatGrid<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        StatColumns { content }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.surfaceMuted))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }
}

/// Equal columns 16 pt apart: four when each can be at least 150 pt wide, otherwise two. Tiles in a row share
/// the tallest tile's height. (macOS 14 has no subview iteration, so this is a small `Layout`.)
private struct StatColumns: Layout {
    private static let gap = Space.s4

    private func columns(for width: CGFloat) -> Int {
        width >= 4 * Metrics.factsTerm + 3 * Self.gap ? 4 : 2
    }

    private struct Rows {
        let count: Int
        let column: CGFloat
        let heights: [CGFloat]
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> Rows {
        let count = columns(for: width)
        let column = (width - CGFloat(count - 1) * Self.gap) / CGFloat(count)
        let heights = stride(from: 0, to: subviews.count, by: count).map { start in
            subviews[start..<min(start + count, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
        }
        return Rows(count: count, column: column, heights: heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 4 * Metrics.factsTerm + 3 * Self.gap
        let layout = rows(subviews, width: width)
        let height = layout.heights.reduce(0, +) + Self.gap * CGFloat(max(0, layout.heights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = rows(subviews, width: bounds.width)
        var y = bounds.minY
        for (row, height) in layout.heights.enumerated() {
            let start = row * layout.count
            for (offset, subview) in subviews[start..<min(start + layout.count, subviews.count)].enumerated() {
                subview.place(
                    at: CGPoint(x: bounds.minX + CGFloat(offset) * (layout.column + Self.gap), y: y),
                    anchor: .topLeading, proposal: ProposedViewSize(width: layout.column, height: height))
            }
            y += height + Self.gap
        }
    }
}

/// One term and its value, with an optional comparison line ("+3 since yesterday"). Static and untoned; the
/// value is already formatted by the caller.
struct StatTile: View {
    let term: String
    let value: String
    var comparison: String?

    init(_ term: String, value: String, comparison: String? = nil) {
        self.term = term
        self.value = value
        self.comparison = comparison
    }

    init(_ term: String, value: Int, comparison: String? = nil) {
        self.init(term, value: value.formatted(), comparison: comparison)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(term).textRole(.label, lineBox: false).foregroundStyle(Theme.inkBody)
            Text(verbatim: value).textRole(.metric, lineBox: false).foregroundStyle(Theme.ink).monospacedDigit()
            if let comparison {
                Text(comparison).textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted).monospacedDigit()
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

/// One term and value for `Facts`.
struct Fact: Identifiable {
    let id = UUID()
    let term: String
    let value: String
    /// Paths, ids and hashes render whole in monospace.
    var monospaced = false

    init(_ term: String, _ value: String, monospaced: Bool = false) {
        self.term = term
        self.value = value
        self.monospaced = monospaced
    }
}

/// Term and value pairs (Ledger PropertyList): a 150 pt muted term column, values in ink, never truncated.
struct Facts<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2Half) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Facts where Content == ForEach<[Fact], UUID, FactRow<Text>> {
    init(_ items: [Fact]) {
        self.init {
            ForEach(items) { item in
                FactRow(item.term) {
                    Text(verbatim: item.value)
                        .font(item.monospaced ? TextRole.mono.font : TextRole.body.font)
                }
            }
        }
    }
}

/// One row of `Facts`: the term, then any value view (a `ShortId`, a badge, text).
struct FactRow<Value: View>: View {
    let term: String
    @ViewBuilder var value: Value

    init(_ term: String, @ViewBuilder value: () -> Value) {
        self.term = term
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Text(term)
                .foregroundStyle(Theme.inkMuted)
                .frame(width: Metrics.factsTerm, alignment: .leading)
            value
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textRole(.body, lineBox: false)
        .accessibilityElement(children: .combine)
    }
}
