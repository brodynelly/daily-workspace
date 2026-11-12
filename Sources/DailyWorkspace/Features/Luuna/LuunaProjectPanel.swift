import DailyCore
import SwiftUI

/// The selected project's Luuna binding, read-only. With a binding it shows the connection, the bound project's
/// identity and facts, and its component status, each with when it was last observed; values kept from an earlier
/// read are marked stale. Without one it offers to link a Luuna project. Linking and unlinking change only the
/// app's `associations.json`; nothing is ever sent to Luuna but its read-only GETs.
struct LuunaProjectPanel: View {
    let association: ProjectAssociation?

    @EnvironmentObject private var luuna: LuunaStore
    @EnvironmentObject private var projects: ProjectsStore
    @State private var projectID = ""
    @State private var picked: String?
    @State private var message: String?

    var body: some View {
        Panel("Luuna", variant: .subpanel) {
            if association?.luuna != nil {
                Button("Unlink") { message = projects.unbindLuuna() }
                    .buttonStyle(.workspace(.secondary, size: .small))
                    .disabled(!projects.canEditAssociations)
                    .help("Remove the binding from associations.json. Nothing changes in Luuna.")
            }
        } content: {
            ObservedSourceLine(status: LuunaStatusWords.connection(luuna))
            if let binding = association?.luuna {
                bound(binding)
            } else {
                link
            }
            if let message { ReasonNote(message, tone: .danger) }
        }
    }

    // MARK: Bound

    @ViewBuilder private func bound(_ binding: LuunaProjectBinding) -> some View {
        let view = luuna.project.value
        Facts {
            FactRow("Runtime") { Text(verbatim: binding.origin.description).font(TextRole.mono.font) }
            FactRow("Project ID") { Text(verbatim: binding.projectID).font(TextRole.mono.font) }
            if let record = view?.project {
                FactRow("Name") { Text(verbatim: record.name) }
                if let revision = record.revision { FactRow("Revision") { Text(verbatim: "\(revision)") } }
                if let hash = record.manifestHash {
                    FactRow("Manifest hash") { Text(verbatim: hash).font(TextRole.mono.font) }
                }
                if let updated = record.updatedAt { FactRow("Updated") { Text(verbatim: updated) } }
            }
            ForEach(Array((view?.repositories ?? []).enumerated()), id: \.offset) { _, repository in
                FactRow("Repository") {
                    Text(
                        verbatim: [repository.repositoryID, repository.localPath].compactMap { $0 }.joined(
                            separator: " ")
                    )
                    .font(TextRole.mono.font)
                }
            }
        }
        LuunaObservedNote(name: "Project", observation: luuna.project, origin: luuna.origin)
        components
    }

    @ViewBuilder private var components: some View {
        if let status = luuna.components.value {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(status.enabled ? "Components enabled" : "Components not enabled")
                    .textRole(.bodyStrong, lineBox: false)
                    .foregroundStyle(Theme.ink)
                if let reason = status.reason {
                    Text(verbatim: reason).textRole(.bodySmall, lineBox: false).foregroundStyle(Theme.inkBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array((status.adapters ?? []).enumerated()), id: \.offset) { _, adapter in
                    HStack(spacing: Space.s2) {
                        Text(verbatim: adapter.name.rawValue).font(TextRole.mono.font).foregroundStyle(Theme.ink)
                        if let state = adapter.status { StatusBadge(state.rawValue, tone: nil) }
                        if let backend = adapter.backendStatus { Tag("backend \(backend.rawValue)") }
                        if let repository = adapter.repositoryID { ShortId(repository, kind: "repository id") }
                    }
                }
            }
        }
        LuunaObservedNote(name: "Component status", observation: luuna.components, origin: luuna.origin)
    }

    // MARK: Link

    @ViewBuilder private var link: some View {
        let available = luuna.isConnected ? luuna.projects.value ?? [] : []
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Link a Luuna project")
                .textRole(.bodyStrong, lineBox: false)
                .foregroundStyle(Theme.ink)
            Text(
                available.isEmpty
                    ? "Not connected, so the ID is not checked. It is bound to \(luuna.origin.description)."
                    : "Choose one of the projects on \(luuna.origin.description)."
            )
            .textRole(.bodySmall, lineBox: false)
            .foregroundStyle(Theme.inkMuted)
            HStack(spacing: Space.s2) {
                if available.isEmpty {
                    BoxedTextField("Luuna project ID", text: $projectID, monospaced: true, onSubmit: bind)
                } else {
                    Picker("Luuna project", selection: $picked) {
                        Text("Choose a project").tag(String?.none)
                        ForEach(available) { record in
                            Text(verbatim: "\(record.name) · \(record.id)").tag(Optional(record.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Button("Link", action: bind)
                    .buttonStyle(.primary)
                    .disabled(!projects.canEditAssociations || chosenID.isEmpty)
            }
        }
    }

    private var chosenID: String {
        let id = luuna.isConnected && !(luuna.projects.value ?? []).isEmpty ? picked ?? "" : projectID
        return id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bind() {
        guard !chosenID.isEmpty else { return }
        message = projects.bindLuuna(origin: luuna.origin, projectID: chosenID)
        if message == nil { projectID = "" }
    }
}
