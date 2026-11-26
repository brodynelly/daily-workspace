import SwiftUI

extension AppModel.CaptureDestination {
    /// Explain the selected owner before saving; the save is still performed by AppModel.
    var hint: String {
        switch self {
        case .task: return "Due today · saved in your local tasks"
        case .note: return "Appended as a list item to today's note in the vault"
        case .quickNotes: return "Review an entry in 02-areas/personal-development/quick-notes.md"
        case .inbox: return "Name and review a new Markdown note directly in 00-inbox/"
        }
    }

    var captureSymbol: String {
        switch self {
        case .task: return "checklist"
        case .note: return "note.text"
        case .quickNotes: return "text.badge.plus"
        case .inbox: return "tray.full"
        }
    }

    var captureSummary: String {
        switch self {
        case .task: return "An action for today"
        case .note: return "A thought to keep"
        case .quickNotes: return "A small idea for later review"
        case .inbox: return "A substantial idea with its own note"
        }
    }
}

/// A destination is a full-width choice, not a cramped segment beside the editor.
private struct CaptureDestinationOption: View {
    let destination: AppModel.CaptureDestination
    let selected: Bool
    let select: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: destination.captureSymbol)
                    .font(.system(size: Metrics.iconSize))
                    .frame(width: Space.s6, height: Space.s6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.sHalf) {
                    Text(destination.title)
                        .textRole(.label, lineBox: false)
                        .foregroundStyle(Theme.ink)
                    Text(destination.captureSummary)
                        .textRole(.caption, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: Metrics.iconSize))
                        .foregroundStyle(Theme.ink)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Space.s12, alignment: .leading)
            .padding(Space.s3)
            .background(
                selected ? Theme.controlSelected : hovered ? Theme.fill : Theme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: Radius.md)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(selected ? Theme.borderStrong : Theme.border, lineWidth: Metrics.borderWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(destination.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(destination.hint)
    }
}

/// The ⌘N sheet and floating Capture window share the same save action and destination choices.
struct CaptureForm: View {
    enum Style { case sheet, window }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let style: Style
    @State private var text = ""
    @State private var destination = AppModel.CaptureDestination.task
    @State private var captureError: String?
    @State private var showVaultReview = false
    @FocusState private var focused: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            heading
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Save to")
                    .textRole(.label, lineBox: false)
                    .foregroundStyle(Theme.ink)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.s3) {
                    ForEach(AppModel.CaptureDestination.allCases) { option in
                        CaptureDestinationOption(destination: option, selected: destination == option) {
                            destination = option
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(destination == .task ? "Task" : "Note")
                    .textRole(.label, lineBox: false)
                    .foregroundStyle(Theme.ink)
                TextField(
                    "", text: $text,
                    prompt: Text(destination == .task ? "What needs doing?" : "What would you like to remember?")
                        .foregroundStyle(Theme.inkMuted),
                    axis: .vertical
                )
                .lineLimit(4...8)
                .focused($focused)
                .onSubmit(commit)
                .fieldChrome(focused: focused)
                .accessibilityLabel(destination == .task ? "Task" : "Note")
                Text(destination.hint)
                    .textRole(.caption, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
            }
            if let captureError { ReasonNote(captureError, tone: .danger) }
            Hairline()
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button(destination == .quickNotes || destination == .inbox ? "Review…" : "Capture", action: commit)
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isEmpty)
            }
        }
        .padding(style == .sheet ? Space.s6 : Space.s5)
        .frame(width: 600)
        .background(Theme.surfaceOverlay)
        .onAppear { focused = true }
        .sheet(isPresented: $showVaultReview) {
            VaultNoteReviewSheet(
                source: destination == .quickNotes ? .quickNotes : .inbox, draft: text,
                onDraftChange: { text = $0 }
            ) {
                text = ""
                captureError = nil
                dismiss()
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: Metrics.iconSize))
                .foregroundStyle(Theme.ink)
                .frame(width: Metrics.controlLg, height: Metrics.controlLg)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Quick Capture")
                    .textRole(.sectionTitle, lineBox: false)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Capture a local task, today's note, Quick Notes, or a named Inbox note.")
                    .textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func commit() {
        if destination == .quickNotes || destination == .inbox {
            showVaultReview = true
            return
        }
        switch model.capture(text, to: destination) {
        case .captured:
            text = ""
            captureError = nil
            dismiss()
        case .rejected(let why):
            captureError = why
        }
    }
}
