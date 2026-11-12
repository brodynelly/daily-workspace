import DailyCore
import SwiftUI

/// Projects: the hubs in `01-projects` on a rail, and the selected hub as one detail card with its purpose,
/// decisions, repositories, Seeds work, Plot coordination, restart record and Luuna binding. Vault files are only
/// read; the one file this screen changes is the app's own `associations.json`, through `ProjectsStore`.
struct ProjectsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectsStore
    @EnvironmentObject private var vaultSession: VaultSession
    @State private var query = ""

    var body: some View {
        Page {
            PageHeader(title: AppSection.projects.title, description: AppSection.projects.description) {
                Button {
                    Task { await projects.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.workspace(.secondary, size: .large))
                .disabled(projects.isRefreshing)
                .help("Read the hubs, Seeds and Plot again")
            }
            content
        }
        .navigationTitle(AppSection.projects.title)
        .task {
            if projects.hubs == nil { await projects.refresh() }
        }
    }

    @ViewBuilder private var content: some View {
        if vaultSession.vault == nil {
            EmptyState(
                "No vault chosen", description: "Projects are read from the hubs in your vault's 01-projects folder.",
                systemImage: AppSection.projects.symbol, boxed: true
            ) {
                Button("Choose Vault…") { model.chooseVault() }.buttonStyle(.primary)
            }
        } else if let hubs = projects.hubs, hubs.value.isEmpty {
            if hubs.state.isReadable {
                EmptyState(
                    "No project hubs",
                    description: "No Markdown file in 01-projects has type: project in its frontmatter.",
                    systemImage: AppSection.projects.symbol, boxed: true)
            } else {
                EmptyState(
                    "Projects could not be read", description: ProjectRail.status(of: hubs).text,
                    systemImage: AppSection.projects.symbol, boxed: true)
            }
        } else if projects.hubs == nil {
            EmptyState("Reading projects…", systemImage: AppSection.projects.symbol, boxed: true)
        } else {
            HStack(alignment: .top, spacing: Space.s5) {
                ProjectRail(query: $query).frame(width: ProjectRail.width)
                ProjectDetailCard()
            }
        }
    }
}

/// The rail: a filter field, the hubs read's state, then one compact row per hub (title, folder and its open
/// Seeds issue count).
struct ProjectRail: View {
    static let width: CGFloat = 280

    @Binding var query: String
    @EnvironmentObject private var projects: ProjectsStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SearchField("Filter projects", text: $query)
            if let hubs = projects.hubs { ObservedSourceLine(status: Self.status(of: hubs)) }
            if shown.isEmpty {
                EmptyState("No project matches “\(query)”")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, hub in
                        ProjectRailRow(
                            hub: hub, openIssues: openIssues(hub), selected: projects.selectedSlug == hub.slug,
                            divider: index > 0
                        ) { projects.select(hub.slug) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .cardSurface()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Project hubs")
            }
        }
    }

    static func status(of hubs: SourceObservation<[ProjectHub]>) -> ObservedSource {
        let count = hubs.value.count
        return ObservedSource("01-projects", observation: hubs, summary: count == 1 ? "1 hub" : "\(count) hubs")
    }

    private var shown: [ProjectHub] {
        let hubs = projects.hubs?.value ?? []
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return hubs }
        return hubs.filter { hub in
            [hub.title, hub.slug, hub.folder, hub.projectKey].contains { $0.localizedCaseInsensitiveContains(text) }
                || hub.tags.contains { $0.localizedCaseInsensitiveContains(text) }
        }
    }

    /// Open Seeds issues labelled `project:<projectKey>`; nil when Seeds holds nothing readable.
    private func openIssues(_ hub: ProjectHub) -> Int? {
        guard let seeds = projects.seeds, seeds.state.isReadable || seeds.lastSuccessAt != nil else { return nil }
        return seeds.value.issues.filter { $0.project == hub.projectKey && !$0.isDoneInSource }.count
    }
}

/// One hub on the rail. The selected row carries the accent (selection); hover changes only the background.
private struct ProjectRailRow: View {
    let hub: ProjectHub
    let openIssues: Int?
    let selected: Bool
    let divider: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: Space.sHalf) {
                    Text(verbatim: hub.title)
                        .textRole(selected ? .bodyStrong : .body, lineBox: false)
                        .foregroundStyle(selected ? Theme.accentText : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: hub.folder)
                        .font(TextRole.caption.font.monospaced())
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let openIssues {
                    Text(openIssues == 1 ? "1 open" : "\(openIssues) open")
                        .textRole(.caption, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .monospacedDigit()
                        .help("Open Seeds issues labelled project:\(hub.projectKey)")
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight, alignment: .leading)
            .background(selected ? Theme.accentSoft : hovered ? Theme.fill : .clear)
            .overlay(alignment: .top) { if divider { Hairline() } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
