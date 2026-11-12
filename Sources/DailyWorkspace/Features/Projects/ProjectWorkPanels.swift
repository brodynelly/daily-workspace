import DailyCore
import SwiftUI

/// The project's Seeds issues and plans, matched on `project:<projectKey>`, with their statuses verbatim. Read-only:
/// the only action opens the owning store file.
struct ProjectSeedsPanel: View {
    let detail: ProjectDetail

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectsStore
    @State private var showClosed = false

    var body: some View {
        let records = detail.issues + detail.plans
        let closed = records.filter(\.isDoneInSource).count
        let shown = records.filter { showClosed || !$0.isDoneInSource }
        Panel(
            "Work (Seeds)", description: "Issues and plans labelled project:\(detail.hub.projectKey) in .seeds/.",
            variant: .subpanel
        ) {
            if closed > 0 {
                Toggle(isOn: $showClosed) { Text("Show closed (\(closed))") }.toggleStyle(.quiet)
            }
        } content: {
            ObservedSourceLine(
                status: ObservedSource(
                    "Seeds", observation: projects.seeds,
                    summary: "\(count(detail.issues.count, "issue")) and \(count(detail.plans.count, "plan"))",
                    notSetUp: "no .seeds/ folder"))
            if !shown.isEmpty {
                RecordList(variant: .rows) {
                    ForEach(shown, id: \.self) { record in row(record) }
                }
            }
        }
    }

    private func row(_ record: SeedsRecord) -> some View {
        RecordRow {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1Half) {
                    Text(verbatim: record.title ?? record.id)
                        .textRole(.body, lineBox: false)
                        .foregroundStyle(record.isDoneInSource ? Theme.inkMuted : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s2) {
                        if let status = record.status, !status.isEmpty {
                            StatusBadge(status, tone: LoopTone.tone(authority: .seeds, nativeStatus: status))
                        }
                        Tag(record.store == .plans ? "plan" : record.type ?? "issue")
                        ShortId(record.id, kind: "Seeds id")
                    }
                    Text(verbatim: meta(record))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Open source") { model.openSource(of: record.openLoop(observedAt: Date())) }
                    .buttonStyle(.workspace(.secondary, size: .small))
                    .help("Reveal \(record.store.path) in Finder")
            }
        }
    }

    private func meta(_ record: SeedsRecord) -> String {
        [
            record.updatedAtRaw.map { "Updated \($0)" },
            record.closedAt.map { "Closed \($0.raw)" },
            "\(record.store.path):\(record.line)",
        ]
        .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Plots that coordinate the project, each with its status verbatim and its latest events. Read-only.
struct ProjectPlotPanel: View {
    let detail: ProjectDetail
    /// Events shown per Plot, newest first.
    var eventLimit = 4

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectsStore

    var body: some View {
        Panel(
            "Coordination (Plot)", description: "Plots that attach this project's issues, its notes or its label.",
            variant: .subpanel
        ) {
            ObservedSourceLine(
                status: ObservedSource(
                    "Plot", observation: projects.plots, summary: count(detail.plots.count, "plot"),
                    notSetUp: "no .plot/ folder"))
            if !detail.plots.isEmpty {
                RecordList(variant: .rows) {
                    ForEach(detail.plots, id: \.id) { plot in row(plot) }
                }
            }
        }
    }

    private func row(_ plot: PlotRecord) -> some View {
        RecordRow {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1Half) {
                    Text(verbatim: plot.title.isEmpty ? plot.id : plot.title)
                        .textRole(.body, lineBox: false)
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: Space.s2) {
                        StatusBadge(plot.status, tone: LoopTone.tone(authority: .plot, nativeStatus: plot.status))
                        ShortId(plot.id, kind: "Plot id")
                    }
                    if let goal = plot.goal, !goal.isEmpty {
                        Text(verbatim: goal).foregroundStyle(Theme.inkBody).fixedSize(horizontal: false, vertical: true)
                    }
                    events(plot)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Open source") { model.openSource(of: plot.openLoop(observedAt: Date())) }
                    .buttonStyle(.workspace(.secondary, size: .small))
                    .help("Reveal \(plot.path) in Finder")
            }
        }
    }

    @ViewBuilder private func events(_ plot: PlotRecord) -> some View {
        let recent = Array(plot.events.reversed().prefix(eventLimit))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(recent, id: \.line) { event in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(verbatim: event.kind).font(TextRole.caption.font.monospaced()).foregroundStyle(
                            Theme.inkBody)
                        Text(verbatim: [event.actor, time(event)].compactMap { $0 }.joined(separator: " · "))
                            .foregroundStyle(Theme.inkMuted)
                        if let text = event.text {
                            Text(verbatim: text).foregroundStyle(Theme.inkBody).fixedSize(
                                horizontal: false, vertical: true)
                        }
                    }
                }
                if plot.events.count > recent.count {
                    Text("\(plot.events.count - recent.count) earlier events").foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(.top, Space.s1)
        }
    }

    private func time(_ event: PlotEvent) -> String? {
        event.at.map { ObservedSource.time($0) } ?? event.atRaw
    }
}

/// `1 issue`, `3 issues`.
private func count(_ value: Int, _ noun: String) -> String {
    value == 1 ? "1 \(noun)" : "\(value) \(noun)s"
}
