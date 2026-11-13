import DailyCore
import SwiftUI

/// Open Loops: local tasks, Reminders and opted-in Mail, with native statuses and source states.
struct OpenLoopsView: View {
    @EnvironmentObject private var loops: OpenLoopsStore
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var reminders: RemindersService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter = OpenLoopsFilter()
    @State private var composer: LoopComposer.Owner?

    var body: some View {
        Page {
            PageHeader(title: AppSection.openLoops.title, description: AppSection.openLoops.description) {
                headerActions
            }
            if let composer {
                LoopComposer(owner: composer) { self.composer = nil }
            }
            stats
            sources
            filters
            feedback
            list
        }
        .navigationTitle(AppSection.openLoops.title)
        .task {
            if loops.observations[.reminders] == nil { await loops.refresh() }
        }
    }

    // MARK: Header

    @ViewBuilder private var headerActions: some View {
        Button {
            Task { await loops.refresh() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.workspace(.secondary, size: .large))
        .disabled(loops.isRefreshing)
        .help("Refresh Reminders and Mail when opted in")
        Button {
            composer = .reminder
        } label: {
            Label("New reminder", systemImage: "list.bullet")
        }
        .buttonStyle(.workspace(.secondary, size: .large))
        .help("Add to your default Apple Reminders list")
        Button {
            composer = .task
        } label: {
            Label("New task", systemImage: "plus")
        }
        .buttonStyle(.workspace(.primary, size: .large))
        .help("Add a local task to tasks.json")
    }

    // MARK: Counts and sources

    private var stats: some View {
        let counts = loops.counts
        let reporting = OpenLoopsStore.authorities.filter { loops.observations[$0]?.state.isReadable == true }.count
        return StatGrid(label: "Open loop counts") {
            StatTile("Open", value: counts.open)
            StatTile("Due today", value: counts.dueToday)
            StatTile("Overdue", value: counts.overdue)
            StatTile("Sources reporting", value: "\(reporting) of \(OpenLoopsStore.authorities.count)")
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(OpenLoopsStore.authorities, id: \.self) { authority in
                ObservedSourceLine(status: status(of: authority))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Source status")
    }

    /// Spell out Mail consent separately from Mail's Automation permission and read state.
    private func status(of authority: LoopAuthority) -> ObservedSource {
        if authority == .reminders, reminders.status != .authorized {
            return ObservedSource(tone: .attention, text: "Reminders: \(reminders.status.label)")
        }
        if authority == .mail {
            if !loops.mailEnabled {
                return ObservedSource(tone: .neutral, text: "Mail: off — enable read-only access in Settings")
            }
            if loops.observations[.mail]?.state == .unauthorized {
                return ObservedSource(
                    tone: .attention, text: "Mail: permission denied — allow Automation access in System Settings")
            }
        }
        let observation = loops.observations[authority]
        let open = observation?.value.filter { !$0.isDoneInSource }.count ?? 0
        return ObservedSource(
            authority.ownerName, observation: observation, summary: open == 0 ? "nothing open" : "\(open) open")
    }

    // MARK: Filters

    private var filters: some View {
        HStack(spacing: Space.s3) {
            SegmentedControl(
                "Source", selection: $filter.source, options: LoopSourceFilter.allCases.map { ($0, $0.title) })
            ProjectFilterMenu(projects: OpenLoopsFilter.projects(in: loops.loops), selection: $filter.project)
            Spacer(minLength: Space.s3)
            Toggle(isOn: $filter.showDone) { Text("Show done") }.toggleStyle(.quiet)
        }
    }

    // MARK: Feedback from the app's own stores

    @ViewBuilder private var feedback: some View {
        if let message = tasks.message { Callout(message, tone: .danger) }
        if let error = reminders.error { Callout(error, tone: .danger) }
        if let deleted = tasks.recentlyDeleted {
            Callout {
                HStack(spacing: Space.s3) {
                    Text("Deleted “\(deleted.title)” from tasks.json")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Undo") { tasks.undoDelete() }.buttonStyle(.workspace(.secondary, size: .small))
                    Button("Dismiss") { tasks.dismissUndo() }.buttonStyle(.text)
                }
            }
        }
    }

    // MARK: List

    private var list: some View {
        let shown = filter.apply(to: loops.loops)
        return Panel(filter.showDone ? "All items" : "Open items") {
            Text(verbatim: shown.count.formatted()).textRole(.bodySmall, lineBox: false).foregroundStyle(Theme.inkMuted)
        } content: {
            if shown.isEmpty {
                emptyList
            } else {
                RecordList(variant: .rows) {
                    ForEach(shown) { OpenLoopRow(loop: $0) }
                }
                .animation(Motion.stateChange(reduceMotion: reduceMotion), value: shown.map(\.id))
            }
        }
    }

    @ViewBuilder private var emptyList: some View {
        if filter.source == .reminders, reminders.status != .authorized {
            RemindersAccessState()
        } else if let authority = filter.source.authority, loops.observations[authority]?.state.isReadable != true {
            EmptyState(
                "\(authority.ownerName) could not be read", description: status(of: authority).text,
                systemImage: AppSection.openLoops.symbol)
        } else {
            let unread = OpenLoopsStore.authorities.filter { loops.observations[$0]?.state.isReadable != true }
            EmptyState(
                (filter.showDone ? "No items" : "Nothing open") + (filter.project.map { " for project:\($0)" } ?? ""),
                description: unread.isEmpty || filter.source != .all
                    ? nil
                    : "Only the sources that were read are counted. "
                        + "\(unread.map(\.ownerName).formatted(.list(type: .and))) could not be read.",
                systemImage: AppSection.openLoops.symbol)
        }
    }
}

/// The project filter: every project slug an owner states, or all.
private struct ProjectFilterMenu: View {
    let projects: [String]
    @Binding var selection: String?

    var body: some View {
        Menu {
            Button("All projects") { selection = nil }
            if !projects.isEmpty { Divider() }
            ForEach(projects, id: \.self) { slug in
                Button("project:\(slug)") { selection = slug }
            }
        } label: {
            Text(selection.map { "project:\($0)" } ?? "All projects")
        }
        .menuStyle(.button)
        .buttonStyle(.secondary)
        .fixedSize()
        .accessibilityLabel("Project")
    }
}
