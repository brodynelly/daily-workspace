import SwiftUI

/// The inline capture form's state. "Captured" is set only from a `.captured` outcome, which `AppModel.capture`
/// returns only after the text reached disk; a rejection keeps the draft and says why.
struct TodayCaptureState: Equatable {
    enum Status: Equatable {
        case captured(AppModel.CaptureDestination)
        case failed(String)
    }

    var draft = ""
    var destination = AppModel.CaptureDestination.task
    private(set) var status: Status?

    var canCapture: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var requiresVaultReview: Bool { destination == .quickNotes || destination == .inbox }

    /// Record the outcome of saving `draft`. Returns true when it was captured.
    @discardableResult
    mutating func apply(_ outcome: AppModel.CaptureOutcome) -> Bool {
        switch outcome {
        case .captured:
            draft = ""
            status = .captured(destination)
            return true
        case .rejected(let why):
            status = .failed(why)
            return false
        }
    }

    /// Typing a new draft clears the last confirmation (clearing the field after a capture does not). A failure's
    /// reason stays until the next attempt.
    mutating func edited() {
        if case .captured = status, !draft.isEmpty { status = nil }
    }
}

/// Capture without leaving Today: a text field, an explicit destination and one primary action.
struct TodayCaptureSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var state = TodayCaptureState()
    @State private var showVaultReview = false
    @FocusState private var focused: Bool

    /// Called after a durable save, so Today can re-read what changed.
    var onCaptured: () -> Void = {}

    var body: some View {
        Panel("Capture") {
            field
            HStack(alignment: .center, spacing: Space.s3) {
                Picker("Save to", selection: $state.destination) {
                    ForEach(AppModel.CaptureDestination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer(minLength: 0)
                Button(state.requiresVaultReview ? "Review…" : "Capture", action: commit)
                    .buttonStyle(.primary)
                    .disabled(!state.canCapture)
            }
            statusLine
        }
        .onChange(of: state.draft) { state.edited() }
        .sheet(isPresented: $showVaultReview) {
            VaultNoteReviewSheet(
                source: state.destination == .quickNotes ? .quickNotes : .inbox,
                draft: state.draft,
                onDraftChange: { state.draft = $0 }
            ) {
                state.apply(.captured)
                onCaptured()
            }
        }
    }

    private var field: some View {
        TextField(
            "Capture a thought…", text: $state.draft,
            prompt: Text("Capture a thought…").foregroundStyle(Theme.inkMuted)
        )
        .textFieldStyle(.plain)
        .font(TextRole.body.font)
        .foregroundStyle(Theme.ink)
        .focused($focused)
        .onSubmit(commit)
        .padding(.horizontal, Space.s3)
        .frame(height: Metrics.controlMd)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.field))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(focused ? Theme.focusRing : Theme.borderStrong, lineWidth: Metrics.borderWidth)
        }
        .accessibilityLabel("Capture text")
    }

    @ViewBuilder private var statusLine: some View {
        switch state.status {
        case .captured(let destination):
            HStack(alignment: .firstTextBaseline, spacing: Space.s1Half) {
                ToneMark(tone: .success).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(captureConfirmation(destination))
            }
            .textRole(.bodySmall, lineBox: false)
            .foregroundStyle(Theme.inkBody)
            .accessibilityElement(children: .combine)
        case .failed(let why):
            ReasonNote(why, tone: .danger, next: "Your text is kept. Try again, or choose the other destination.")
        case nil:
            EmptyView()
        }
    }

    private func captureConfirmation(_ destination: AppModel.CaptureDestination) -> String {
        switch destination {
        case .task: "Captured as a task for today."
        case .note: "Captured to today's note."
        case .quickNotes: "Saved to Quick Notes."
        case .inbox: "Saved to Inbox."
        }
    }

    private func commit() {
        guard state.canCapture else { return }
        if state.requiresVaultReview {
            showVaultReview = true
            return
        }
        if state.apply(model.capture(state.draft, to: state.destination)) { onCaptured() }
    }
}
