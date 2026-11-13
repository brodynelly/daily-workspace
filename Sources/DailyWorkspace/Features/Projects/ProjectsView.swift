import DailyCore
import SwiftUI

/// Projects: vault hubs retain their purpose and context; bound Luuna projects show native read-only work.
/// The app changes only its own associations.json when linking or unlinking.
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
                .help("Read the project hubs again")
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

/// The rail: a filter field, hub read state and compact hub identity rows.
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
                            hub: hub, selected: projects.selectedSlug == hub.slug,
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

}

/// One hub on the rail. The selected row carries the accent (selection); hover changes only the background.
private struct ProjectRailRow: View {
    let hub: ProjectHub
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
                if selected {
                    Text("Selected")
                        .textRole(.caption, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
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
