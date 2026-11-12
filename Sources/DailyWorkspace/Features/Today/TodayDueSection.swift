import DailyCore
import SwiftUI

/// "Due today": overdue items first, then items whose own date is today, as compact record rows. Each row shows
/// the owner's status verbatim and its source. Local tasks complete through `TaskStore`; Org rows only open their
/// file. Nothing here writes to Org, Seeds or Plot.
struct TodayDueSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var openLoops: OpenLoopsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let day: LocalDay

    private var items: [TodayDueItem] { TodayDue.items(from: openLoops, on: day) }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionHeading("Due today") {
                Button("Open Loops") { model.navigation.section = .openLoops }
                    .buttonStyle(.text)
                    .accessibilityLabel("Show every open loop")
            }
            if items.isEmpty {
                Text(emptyText)
                    .textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.vertical, Space.s2)
            } else {
                RecordList(variant: .rows) {
                    ForEach(items) { DueRow(item: $0, day: day) }
                }
                .accessibilityLabel("Due today")
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: items.map(\.id))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyText: String {
        openLoops.isRefreshing && openLoops.loops.isEmpty ? "Reading your sources…" : "Nothing is due today."
    }
}

/// One due item: the title with when it is due and where it lives, then the native status badge, the source tag and
/// the one action its owner allows here.
private struct DueRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var openLoops: OpenLoopsStore
    @EnvironmentObject private var tasks: TaskStore

    let item: TodayDueItem
    let day: LocalDay

    private var loop: OpenLoop { item.loop }

    var body: some View {
        RecordRow(title: loop.title, meta: meta) {
            if item.isOverdue { Tag("overdue") }
            StatusBadge(loop.nativeStatus, tone: TodayDue.tone(for: loop))
            Tag(TodayDue.sourceName(loop.authority))
            // A fixed action column keeps the badges and tags of every row aligned.
            action.frame(minWidth: 96, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
    }

    private var meta: String? {
        let parts = [TodayDue.when(item, on: day), loop.authority == .org ? loop.sourcePath : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var action: some View {
        switch loop.authority {
        case .local:
            if let task = openLoops.task(for: loop) {
                Button(task.isCompleted ? "Reopen" : "Complete") { tasks.toggle(task) }
                    .buttonStyle(.text)
                    .accessibilityLabel(task.isCompleted ? "Reopen \(loop.title)" : "Complete \(loop.title)")
            }
        case .org:
            if loop.sourceLink != nil {
                Button("Open source") { model.openSource(of: loop) }
                    .buttonStyle(.text)
                    .accessibilityLabel("Open \(loop.title) in \(loop.sourcePath ?? "its Org file")")
            }
        case .seeds, .plot, .reminders, .luuna:
            EmptyView()
        }
    }
}
