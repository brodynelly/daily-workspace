import DailyCore
import SwiftUI

/// The Assistant's side rail (Luuna's session history): this conversation's questions, newest first, every path
/// its answers read, and the restart-record draft for a project.
struct AssistantRail: View {
    @EnvironmentObject private var assistant: AssistantSession
    @Binding var reveal: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                questions
                sourcesRead
                RestartDraftControl()
            }
            .padding(.trailing, Space.s2)
        }
    }

    private var questions: some View {
        Panel("This conversation", variant: .plain) {
            if assistant.turns.isEmpty {
                Text("Questions you ask appear here. Nothing is kept after you start over or quit.")
                    .textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                RecordList(variant: .rows) {
                    ForEach(assistant.turns.reversed()) { turn in
                        RecordRow(action: { reveal = turn.id }) {
                            Text(verbatim: turn.question)
                                .textRole(.body, lineBox: false)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                            Text(meta(for: turn))
                                .textRole(.caption, lineBox: false)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var sourcesRead: some View {
        let paths = ToolCitation.unique(assistant.turns.flatMap(\.citations)).filter { $0.kind == .path }
        if !paths.isEmpty {
            Panel("Read in this conversation", variant: .plain) {
                VStack(alignment: .leading, spacing: Space.s1Half) {
                    ForEach(paths, id: \.self) { CitationRow(citation: $0) }
                }
            }
        }
    }

    private func meta(for turn: AssistantTurn) -> String {
        let time = turn.askedAt.formatted(date: .omitted, time: .shortened)
        let lookups = turn.toolCalls.count == 1 ? "1 lookup" : "\(turn.toolCalls.count) lookups"
        return "\(time) · \(lookups)"
    }
}

/// Choose a project and ask for a restart-record draft from this conversation. The draft opens for review.
struct RestartDraftControl: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var assistant: AssistantSession
    @EnvironmentObject private var projects: ProjectsStore
    @EnvironmentObject private var restarts: RestartRecords
    @StateObject private var flow = RestartDraftFlow()
    @State private var slug = ""

    var body: some View {
        Panel(
            "Restart record",
            description:
                "Draft what this conversation decided and the next exact action for a project. Nothing is saved "
                + "until you accept it.",
            variant: .plain
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if hubs.isEmpty {
                    Text(noHubsReason)
                        .textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("Project", selection: $slug) {
                        Text("Choose a project").tag("")
                        ForEach(hubs) { hub in Text(verbatim: hub.title).tag(hub.slug) }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Project")
                }
                HStack(spacing: Space.s2) {
                    Button("Draft restart record") { flow.start(project: slug, assistant: assistant) }
                        .buttonStyle(.secondary)
                        .disabled(slug.isEmpty || assistant.isStreaming || flow.isDrafting)
                    if flow.isDrafting { StreamingDots(label: "Drafting") }
                }
                if let failure = flow.failure {
                    ReasonNote(failure, tone: .danger, next: "Try again, or ask about the project first.")
                }
            }
        }
        .restartReview(flow, restarts: restarts)
    }

    private var hubs: [ProjectHub] { projects.hubs?.value ?? [] }

    private var noHubsReason: String {
        guard model.vaultSession.vault != nil else { return "Choose a vault to list its projects." }
        guard let hubs = projects.hubs else { return "Projects have not been read yet." }
        if let reason = WorkspaceAssistantContext.unreadableReason(hubs) { return "Project hubs \(reason)." }
        return "No project hubs were found in 01-projects."
    }
}
