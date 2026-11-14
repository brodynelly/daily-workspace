import SwiftUI

/// The conversation, oldest first, then the live turn. While the reader is at the bottom, new content keeps it
/// there; scrolling up releases it, and returning to the bottom follows again. Instant under Reduce Motion.
struct AssistantTranscript: View {
    @EnvironmentObject private var assistant: AssistantSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A turn the rail asked to show.
    @Binding var reveal: UUID?

    @State private var following = true

    private static let bottomID = "assistant-transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s6) {
                    if assistant.turns.isEmpty, !assistant.isStreaming {
                        EmptyState(
                            "No questions yet",
                            description:
                                "Ask about a project, what is due or a note. Each answer lists what it read.",
                            systemImage: "text.bubble", boxed: true)
                    }
                    ForEach(assistant.turns) { turn in
                        AssistantTurnView(turn: turn).id(turn.id)
                    }
                    if assistant.isStreaming { AssistantLiveTurn() }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        .onAppear { following = true }
                        .onDisappear { following = false }
                }
                .padding(.trailing, Space.s3)
                .padding(.bottom, Space.s2)
            }
            // Coming back to the screen shows the latest exchange.
            .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .onChange(of: assistant.pendingQuestion) { _, question in
                // A new question always shows its live answer.
                if question != nil { follow(proxy, force: true) }
            }
            .onChange(of: assistant.liveText) { follow(proxy) }
            .onChange(of: assistant.liveToolCalls) { follow(proxy) }
            .onChange(of: assistant.turns.count) { follow(proxy) }
            .onChange(of: reveal) { _, id in
                guard let id else { return }
                withAnimation(Motion.stateChange(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .top) }
                reveal = nil
            }
            .overlay(alignment: .bottomTrailing) {
                if !following, assistant.isStreaming {
                    Button("Latest", systemImage: "arrow.down") { follow(proxy, force: true) }
                        .buttonStyle(.secondary)
                        .padding(Space.s3)
                        .help("Follow the answer as it arrives")
                }
            }
        }
    }

    private func follow(_ proxy: ScrollViewProxy, force: Bool = false) {
        guard following || force else { return }
        following = true
        if reduceMotion {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        } else {
            withAnimation(Motion.easeOut(0.16)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
    }
}

/// One finished exchange: the question, then the answer card.
struct AssistantTurnView: View {
    let turn: AssistantTurn

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            AssistantQuestion(text: turn.question, askedAt: turn.askedAt)
            AssistantAnswerCard(turn: turn)
        }
    }
}

/// The question as asked, on the muted ground.
struct AssistantQuestion: View {
    let text: String
    var askedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Text("You").textRole(.label, lineBox: false).foregroundStyle(Theme.inkMuted)
                if let askedAt {
                    Text(askedAt, format: .dateTime.hour().minute())
                        .textRole(.caption, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                        .monospacedDigit()
                }
            }
            Text(verbatim: text)
                .textRole(.body, lineBox: false)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.surfaceMuted))
    }
}

/// A finished answer: Markdown text, the model that served it when it was a fallback, an "unverified" mark for
/// an uncited status claim, and the lookups behind it.
struct AssistantAnswerCard: View {
    @EnvironmentObject private var navigation: AppNavigation
    let turn: AssistantTurn

    private var noteSources: [String] {
        turn.citations.compactMap { citation in
            citation.kind == .path && citation.value.lowercased().hasSuffix(".md") ? citation.value : nil
        }
    }

    private var suggestedDraft: String {
        turn.finalAnswer + "\n\nSources:\n" + noteSources.map { "- \($0)" }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text("Assistant").textRole(.label, lineBox: false).foregroundStyle(Theme.ink)
                if let fallback = turn.fallbackModel {
                    Tag("Answered by \(fallback)")
                        .help("A server-side fallback answered instead of the model chosen in Settings.")
                }
                if AnswerClaims.isUnverified(answer: turn.answer, citations: turn.citations) {
                    Tag("unverified")
                        .help("This answer mentions a status, but no lookup returned a record ID to back it.")
                        .accessibilityLabel("Unverified: no lookup returned a record ID for this status")
                }
                Spacer(minLength: 0)
            }
            MarkdownText(turn.answer)
            if !noteSources.isEmpty {
                Button("Review draft in Notes", systemImage: "square.and.pencil") {
                    navigation.reviewedAssistantNote = AssistantNoteDraft(text: suggestedDraft, paths: noteSources)
                    navigation.notesMode = .editor
                    navigation.section = .notes
                }
                .buttonStyle(.secondary)
                .help("Open Notes to review the cited text and choose a Markdown path before confirming a save")
            }
            if !turn.toolCalls.isEmpty { ToolCallsDisclosure(calls: turn.toolCalls) }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// The answer being written: the question, the lookups so far, the text so far with a steady caret, and the
/// streaming dots. A restart draft in progress shows only the dots and what it is doing.
struct AssistantLiveTurn: View {
    @EnvironmentObject private var assistant: AssistantSession

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let question = assistant.pendingQuestion { AssistantQuestion(text: question) }
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text("Assistant").textRole(.label, lineBox: false).foregroundStyle(Theme.ink)
                    StreamingDots()
                    Text(status).textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 0)
                }
                if !assistant.liveToolCalls.isEmpty {
                    ToolCallList(calls: assistant.liveToolCalls, live: true)
                }
                if !assistant.liveText.isEmpty {
                    let live = MarkdownText.attributed(assistant.liveText.trimmingCharacters(in: .newlines))
                    Text("\(Text(live))\(Self.caret)")
                        .textRole(.body, lineBox: false)
                        .foregroundStyle(Theme.inkBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(verbatim: assistant.liveText))
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    /// The tail caret: steady (evidence never pulses), in the active tone, and not part of the text.
    private static var caret: Text { Text(verbatim: " ▍").foregroundStyle(Theme.info) }

    private var status: String {
        if assistant.pendingQuestion == nil { return "Drafting a restart record" }
        if assistant.liveToolCalls.contains(where: { $0.citations.isEmpty && !$0.isError }),
            assistant.liveText.isEmpty
        {
            return "Looking things up"
        }
        return assistant.liveText.isEmpty ? "Thinking" : "Answering"
    }
}

/// Inline Markdown (bold, italics, code, links) with the line breaks kept. Falls back to the plain text.
struct MarkdownText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(Self.attributed(text))
            .textRole(.body, lineBox: false)
            .foregroundStyle(Theme.inkBody)
            .tint(Theme.accentText)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// The deliberately simple check behind the "unverified" mark: an answer that mentions a status
/// while no lookup returned a record ID.
enum AnswerClaims {
    static let statusWords: Set<String> = [
        "status", "done", "completed", "closed", "overdue", "blocked", "incomplete", "archived", "in_progress",
    ]

    static func isUnverified(answer: String, citations: [ToolCitation]) -> Bool {
        !citations.contains { $0.kind == .record } && mentionsStatus(answer)
    }

    static func mentionsStatus(_ text: String) -> Bool {
        let words = text.split { !($0.isLetter || $0 == "_") }.map(String.init)
        return words.contains { statusWords.contains($0.lowercased()) }
    }
}
