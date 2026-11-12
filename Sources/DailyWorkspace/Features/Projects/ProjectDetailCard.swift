import DailyCore
import SwiftUI

/// The selected hub as one hairline card: `Projects / {title}`, the title with the hub's tags and project key, its
/// facts, purpose and decisions, then one subpanel per owner (repositories, Seeds, Plot, the restart record and
/// Luuna). Everything here is read from its owner; the only edits are to the app's own association.
struct ProjectDetailCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectsStore

    var body: some View {
        Group {
            if let detail = projects.detail {
                content(detail)
            } else {
                EmptyState(
                    "No project selected",
                    description: "Select a project to see its purpose, repositories, work and coordination.",
                    systemImage: AppSection.projects.symbol)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func content(_ detail: ProjectDetail) -> some View {
        let hub = detail.hub
        return VStack(alignment: .leading, spacing: Space.s4) {
            Breadcrumbs(items: [Crumb(AppSection.projects.title) { projects.select(nil) }, Crumb(hub.title)])
            header(hub)
            Facts {
                FactRow("Hub") { Text(verbatim: hub.path).font(TextRole.mono.font) }
                FactRow("Folder") { Text(verbatim: hub.folder).font(TextRole.mono.font) }
                FactRow("Latest note") { Text(latestNote(hub)) }
            }
            if let purpose = hub.purpose, !purpose.isEmpty {
                Text(verbatim: purpose)
                    .textRole(.body)
                    .foregroundStyle(Theme.inkBody)
                    .frame(maxWidth: Metrics.measure, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack(spacing: Space.s2) {
                Button {
                    model.openNote(hub.path)
                } label: {
                    Label("Open in Notes", systemImage: "doc.text")
                }
                .buttonStyle(.secondary)
                .help("Open \(hub.path) in Notes")
            }
            if !hub.decisions.isEmpty { decisions(hub.decisions) }
            ProjectRepositoriesPanel(detail: detail)
            ProjectSeedsPanel(detail: detail)
            ProjectPlotPanel(detail: detail)
            ProjectRestartSection(slug: hub.slug)
            LuunaProjectPanel(association: detail.association)
        }
    }

    /// The title (the card's h3) with the hub's tags and its Seeds project key as chips.
    private func header(_ hub: ProjectHub) -> some View {
        ChipFlow {
            Text(verbatim: hub.title)
                .textRole(.sectionTitle, lineBox: false)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Tag("project:\(hub.projectKey)")
            ForEach(hub.tags, id: \.self) { Tag($0) }
        }
    }

    private func decisions(_ items: [String]) -> some View {
        Panel("Decisions and Unknowns", variant: .subpanel) {
            VStack(alignment: .leading, spacing: Space.s1Half) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(verbatim: "•").foregroundStyle(Theme.inkMuted).accessibilityHidden(true)
                        Text(verbatim: item)
                            .foregroundStyle(Theme.inkBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .textRole(.body, lineBox: false)
            .frame(maxWidth: Metrics.measure, alignment: .leading)
        }
    }

    private func latestNote(_ hub: ProjectHub) -> String {
        guard let date = hub.latestNoteModified else {
            return hub.notes.isEmpty ? "No notes in notes/" : "Not dated"
        }
        let newest = hub.notes.first { $0.modified == date }?.title
        let day = date.formatted(date: .abbreviated, time: .omitted)
        return newest.map { "\(day) · \($0)" } ?? day
    }
}
