import DailyCore
import SwiftUI

/// A project's latest accepted restart record: the decision, the next exact action, when it was accepted, and
/// its sources, each flagged when the file changed since it was read (hashes computed off the main actor).
/// "Draft a new one" asks the Assistant and opens the review. Self-contained: it needs only the environment's
/// `AppModel`.
struct RestartPanel: View {
    let slug: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        RestartPanelContent(
            slug: slug, restarts: model.restarts, assistant: model.assistant, preferences: model.preferences,
            key: model.assistantKey)
    }
}

struct RestartPanelContent: View {
    enum Load: Equatable {
        case loading
        case loaded(LatestRestart)
        case failed(String)
    }

    let slug: String
    @ObservedObject var restarts: RestartRecords
    @ObservedObject var assistant: AssistantSession
    @ObservedObject var preferences: Preferences
    @ObservedObject var key: AssistantKey
    @StateObject private var flow = RestartDraftFlow()
    @State private var load: Load

    init(
        slug: String, restarts: RestartRecords, assistant: AssistantSession, preferences: Preferences,
        key: AssistantKey, initial: Load = .loading
    ) {
        self.slug = slug
        self.restarts = restarts
        self.assistant = assistant
        self.preferences = preferences
        self.key = key
        _load = State(initialValue: initial)
    }

    var body: some View {
        Panel("Restart record", description: description) {
            Button("Draft a new one") { flow.start(project: slug, assistant: assistant) }
                .buttonStyle(.workspace(.secondary, size: .small))
                .disabled(draftBlocker != nil || assistant.isStreaming || flow.isDrafting)
                .help(draftBlocker ?? "Draft a restart record for \(slug) and review it before anything is saved")
        } content: {
            content
            if flow.isDrafting {
                HStack(spacing: Space.s2) {
                    StreamingDots()
                    Text("Drafting a restart record…").textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            if let failure = flow.failure { ReasonNote(failure, tone: .danger, next: "Try again in a moment.") }
            if let draftBlocker {
                Text(draftBlocker).textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
            }
        }
        .task(id: "\(slug)#\(restarts.revision)") { await reload() }
        .restartReview(flow, restarts: restarts)
    }

    private var description: String {
        "The decision and next exact action from the last accepted session, with the files it was based on."
    }

    /// Why a new draft can't be asked for, or nil.
    private var draftBlocker: String? {
        if !preferences.assistantEnabled { return "Turn on the Assistant in Settings → AI to draft one." }
        if !key.isSaved { return "Save an Anthropic API key in Settings → AI to draft one." }
        return nil
    }

    @ViewBuilder private var content: some View {
        switch load {
        case .loading:
            Text("Reading the restart ledger…").textRole(.bodySmall, lineBox: false).foregroundStyle(Theme.inkMuted)
        case .failed(let reason):
            ReasonNote(reason, tone: .danger, next: "Check that restart-ledger.jsonl in the app folder is readable.")
        case .loaded(let latest):
            if let record = latest.record {
                RestartRecordView(record: record, checks: latest.checks)
            } else {
                EmptyState(
                    "No restart record yet",
                    description: "Accept a drafted record to keep the decision and the next exact action here.")
            }
            if !latest.skippedLines.isEmpty { SkippedLinesNote(lines: latest.skippedLines) }
        }
    }

    private func reload() async {
        switch await restarts.latest(project: slug) {
        case .success(let latest): load = .loaded(latest)
        case .failure(let failure): load = .failed(failure.message)
        }
    }
}

/// One accepted record: its facts, then each source with how it compares with the disk now.
struct RestartRecordView: View {
    let record: RestartRecord
    let checks: [String: SourceCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Facts {
                FactRow("Decision") { Text(verbatim: record.decision) }
                FactRow("Next exact action") { Text(verbatim: record.nextAction).fontWeight(.semibold) }
                if !record.notes.isEmpty { FactRow("Notes") { Text(verbatim: record.notes) } }
                FactRow("Accepted") {
                    Text(record.acceptedAt.formatted(date: .abbreviated, time: .shortened))
                }
                FactRow("Record") { ShortId(record.id.uuidString, kind: "restart record ID") }
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Sources").textRole(.label, lineBox: false).foregroundStyle(Theme.ink)
                if record.sources.isEmpty {
                    Text("This record lists no sources.")
                        .textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                }
                ForEach(record.sources, id: \.path) { source in
                    SourceRow(source: source, check: checks[source.path])
                }
            }
        }
    }
}

private struct SourceRow: View {
    let source: SourceRef
    let check: SourceCheck?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(verbatim: source.path)
                    .font(.system(size: TextRole.caption.size, design: .monospaced))
                    .foregroundStyle(Theme.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                badge
            }
            HStack(spacing: Space.s2) {
                ShortId("sha256:\(source.sha256)", kind: "hash")
                Text("read \(source.observedAt.formatted(date: .abbreviated, time: .shortened))")
                    .textRole(.caption, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.vertical, Space.s1)
    }

    @ViewBuilder private var badge: some View {
        switch check {
        case .changed:
            StatusBadge("changed since you read it", tone: .attention)
        case .missing:
            StatusBadge("missing now", tone: .attention)
        case .unreadable(let reason):
            StatusBadge("can't check", tone: .neutral).help(reason)
        case .unchanged:
            Text("unchanged").textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
        case nil:
            EmptyView()
        }
    }
}
