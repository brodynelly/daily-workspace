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
    @EnvironmentObject private var luunaWork: LuunaWorkStore
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
        work(binding)
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

    @ViewBuilder private func work(_ binding: LuunaProjectBinding) -> some View {
        if binding.origin != luuna.origin {
            ReasonNote(
                "Native work is unavailable: this project belongs to \(binding.origin), not \(luuna.origin).",
                tone: .attention)
        } else if !luuna.isConnected {
            ReasonNote(
                "Native work requires a connected Luuna runtime. No board or tickets are available for this connection.",
                tone: .attention)
        } else {
            Panel("Native work", description: "Read-only board and tickets from Luuna.", variant: .subpanel) {
                Button("Refresh work") { Task { await luunaWork.refresh() } }
                    .buttonStyle(.workspace(.secondary, size: .small))
                    .disabled(luunaWork.isRefreshing)
            } content: {
                board
                tickets
            }
        }
    }

    @ViewBuilder private var board: some View {
        Text("Board").textRole(.bodyStrong, lineBox: false)
        if let board = luunaWork.board.value {
            if let note = board.note { Text(verbatim: note).textRole(.bodySmall, lineBox: false) }
            ForEach(Array(board.columns.enumerated()), id: \.offset) { _, lane in
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack {
                        Text(verbatim: lane.column.title).textRole(.bodyStrong, lineBox: false)
                        ShortId(lane.column.id, kind: "column id")
                    }
                    if let description = lane.column.description {
                        Text(verbatim: description).textRole(.bodySmall, lineBox: false)
                    }
                    if lane.cards.isEmpty { Text("No cards in this lane").foregroundStyle(Theme.inkMuted) }
                    ForEach(Array(lane.cards.enumerated()), id: \.offset) { _, card in
                        VStack(alignment: .leading, spacing: Space.sHalf) {
                            Text(verbatim: card.title)
                            HStack(spacing: Space.s2) {
                                Tag(card.kind.rawValue)
                                if let state = card.state { StatusBadge("Run: \(state.rawValue)", tone: nil) }
                                if let ticketID = card.ticketID { ShortId(ticketID, kind: "ticket id") }
                                if let runID = card.runID { ShortId(runID, kind: "run id") }
                            }
                            if let ticketID = card.ticketID {
                                Button("Show ticket \(ticketID)") { luunaWork.selectTicket(ticketID) }
                                    .buttonStyle(.workspace(.secondary, size: .small))
                            }
                        }
                    }
                }
            }
        } else if luunaWork.board.state == .empty {
            Text("The board has no cards.")
        } else if luunaWork.board.state == .unavailable(.notChecked) {
            Text("The board has not been read on this connection.")
        }
        LuunaObservedNote(name: "Board", observation: luunaWork.board, origin: luuna.origin)
    }

    @ViewBuilder private var tickets: some View {
        Text("Tickets").textRole(.bodyStrong, lineBox: false)
        if let tickets = luunaWork.tickets.value {
            if tickets.isEmpty { Text("Luuna returned no tickets for this project.") }
            ForEach(tickets) { ticket in
                Button {
                    luunaWork.selectTicket(ticket.id)
                } label: {
                    HStack(spacing: Space.s2) {
                        Text(verbatim: ticket.title)
                        ShortId(ticket.id, kind: "ticket id")
                        if let status = ticket.status {
                            StatusBadge(status.rawValue, tone: nil)
                        } else {
                            Tag("Status not supplied")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } else if luunaWork.tickets.state == .empty {
            Text("Luuna returned no tickets for this project.")
        } else if luunaWork.tickets.state == .unavailable(.notChecked) {
            Text("Tickets have not been read on this connection.")
        }
        LuunaObservedNote(name: "Tickets", observation: luunaWork.tickets, origin: luuna.origin)
        if let selectedID = luunaWork.selectedTicketID {
            Text("Ticket detail").textRole(.bodyStrong, lineBox: false)
                .task(id: selectedID) { await luunaWork.refreshSelectedTicket() }
            if let ticket = luunaWork.selectedTicket.value {
                Facts {
                    FactRow("Ticket ID") { Text(verbatim: ticket.id).font(TextRole.mono.font) }
                    FactRow("Project ID") { Text(verbatim: ticket.projectID).font(TextRole.mono.font) }
                    FactRow("Title") { Text(verbatim: ticket.title) }
                    FactRow("Revision") { Text(verbatim: "\(ticket.revision)") }
                    FactRow("Status") { Text(verbatim: ticket.status?.rawValue ?? "Not supplied by Luuna") }
                    if let source = ticket.source { FactRow("Source") { Text(verbatim: source.rawValue) } }
                    if let intent = ticket.intent { FactRow("Intent") { Text(verbatim: intent) } }
                    if let created = ticket.createdAt { FactRow("Created") { Text(verbatim: created) } }
                    if let updated = ticket.updatedAt { FactRow("Updated") { Text(verbatim: updated) } }
                    ForEach(Array((ticket.repositoryIDs ?? []).enumerated()), id: \.offset) { _, id in
                        FactRow("Repository ID") { Text(verbatim: id).font(TextRole.mono.font) }
                    }
                    ForEach(Array((ticket.acceptanceCriteria ?? []).enumerated()), id: \.offset) { _, criterion in
                        FactRow("Acceptance criterion") { Text(verbatim: criterion) }
                    }
                }
            } else if luunaWork.selectedTicket.state == .unavailable(.notChecked) {
                Text("Reading ticket \(selectedID)…")
            }
            LuunaObservedNote(name: "Ticket detail", observation: luunaWork.selectedTicket, origin: luuna.origin)
        }
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
