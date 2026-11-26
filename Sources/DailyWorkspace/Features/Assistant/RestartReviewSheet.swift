import DailyCore
import SwiftUI

/// Asks the Assistant for a restart draft and holds it for review. Nothing is saved here: the review sheet
/// appends to the ledger only when the user accepts.
@MainActor
final class RestartDraftFlow: ObservableObject {
    struct Review: Identifiable {
        let id = UUID()
        var draft: RestartDraft
    }

    @Published var review: Review?
    @Published private(set) var isDrafting = false
    @Published private(set) var failure: String?

    init(review: RestartDraft? = nil) {
        self.review = review.map { Review(draft: $0) }
    }

    func start(project: String, assistant: AssistantSession) {
        guard !isDrafting else { return }
        failure = nil
        isDrafting = true
        Task {
            defer { isDrafting = false }
            do {
                review = Review(draft: try await assistant.draftRestartRecord(project: project))
            } catch is CancellationError {
                return
            } catch let error as AgentError {
                failure = error.message
            } catch {
                failure = "The draft couldn't be made. Try again."
            }
        }
    }
}

extension View {
    /// Presents `flow`'s draft for review.
    func restartReview(_ flow: RestartDraftFlow, restarts: RestartRecords) -> some View {
        modifier(RestartReviewPresenter(flow: flow, restarts: restarts))
    }
}

private struct RestartReviewPresenter: ViewModifier {
    @ObservedObject var flow: RestartDraftFlow
    let restarts: RestartRecords

    func body(content: Content) -> some View {
        content.sheet(item: $flow.review) { review in
            RestartReviewSheet(draft: review.draft, restarts: restarts)
        }
    }
}

/// The review of a drafted restart record: decision, next action and notes are editable, sources can be
/// removed. Accept hashes each source as it is on disk now, then appends; "Saved" shows only after the append
/// returned. Cancel discards the draft.
struct RestartReviewSheet: View {
    enum Phase: Equatable {
        case editing
        case saving
        case saved(RestartRecord, skippedLines: [Int])
        case failed(String)
    }

    @ObservedObject var restarts: RestartRecords
    @State private var draft: RestartDraft
    @State private var phase: Phase
    @Environment(\.dismiss) private var dismiss

    init(draft: RestartDraft, restarts: RestartRecords, phase: Phase = .editing) {
        self.restarts = restarts
        _draft = State(initialValue: draft)
        _phase = State(initialValue: phase)
    }

    var body: some View {
        FormSheet("Review the restart record", description: Self.intro, width: .review, spacing: Space.s5) {
            Tag("project:\(draft.projectSlug)")
        } content: {
            ReviewField(title: "Decision", text: $draft.decision, editable: isEditable)
            ReviewField(title: "Next exact action", text: $draft.nextAction, editable: isEditable)
            ReviewField(title: "Notes", text: $draft.notes, editable: isEditable, height: 52)
            sources
            outcome
            footer
        }
    }

    private static let intro =
        "Edit anything, then accept. Nothing is saved until you do, and each source is hashed as it is on disk at "
        + "that moment."

    private var isEditable: Bool {
        switch phase {
        case .editing, .failed: return true
        case .saving, .saved: return false
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Sources").textRole(.label, lineBox: false).foregroundStyle(Theme.ink)
            if draft.sources.isEmpty {
                Text("No sources. The record keeps the decision and the next action only.")
                    .textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
            }
            ForEach(draft.sources, id: \.path) { source in
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(verbatim: source.path)
                        .font(TextRole.monoCaption.font)
                        .foregroundStyle(Theme.inkBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if !source.observed {
                        Tag("unverified").help("No lookup in this conversation returned this path.")
                    }
                    Spacer(minLength: 0)
                    if isEditable {
                        Button("Remove") { draft.sources.removeAll { $0.path == source.path } }
                            .buttonStyle(.workspace(.quiet, size: .small))
                            .help("Leave \(source.path) out of the record")
                    }
                }
            }
        }
    }

    @ViewBuilder private var outcome: some View {
        switch phase {
        case .editing:
            EmptyView()
        case .saving:
            HStack(spacing: Space.s2) {
                StreamingDots()
                Text("Hashing the sources and saving…").textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
            }
        case .saved(let record, let skipped):
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    StatusBadge("Saved", tone: .neutral)
                    Text("Appended to the restart ledger.").textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkBody)
                    ShortId(record.id.uuidString, kind: "restart record ID")
                }
                if !skipped.isEmpty { SkippedLinesNote(lines: skipped) }
            }
        case .failed(let reason):
            ReasonNote(reason, tone: .danger, next: "Remove the sources that can't be read, or try again.")
        }
    }

    private var footer: some View {
        FormFooter {
            if case .saved = phase {
                Button("Done") { dismiss() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .disabled(phase == .saving)
                Button("Accept", action: accept)
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAccept)
            }
        }
    }

    private var canAccept: Bool {
        isEditable && !draft.decision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func accept() {
        guard canAccept else { return }
        var reviewed = draft
        reviewed.decision = draft.decision.trimmingCharacters(in: .whitespacesAndNewlines)
        reviewed.nextAction = draft.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        reviewed.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .saving
        Task {
            switch await restarts.accept(reviewed) {
            case .saved(let record, let skipped): phase = .saved(record, skippedLines: skipped)
            case .failed(let reason): phase = .failed(reason)
            }
        }
    }
}

/// A labelled multi-line field on the field ground.
private struct ReviewField: View {
    let title: String
    @Binding var text: String
    var editable: Bool
    var height: CGFloat = 64

    var body: some View {
        LabeledField(title) {
            TextArea(title, text: $text, height: height).disabled(!editable)
        }
    }
}

/// Ledger lines that could not be read: reported, never repaired.
struct SkippedLinesNote: View {
    let lines: [Int]

    var body: some View {
        let list = lines.map(String.init).joined(separator: ", ")
        let text =
            lines.count == 1
            ? "Line \(list) of restart-ledger.jsonl could not be read. It is left as it is and skipped."
            : "Lines \(list) of restart-ledger.jsonl could not be read. They are left as they are and skipped."
        Callout(text, tone: .attention)
    }
}
