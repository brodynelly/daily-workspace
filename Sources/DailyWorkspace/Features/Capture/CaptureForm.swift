import SwiftUI

/// "Task for Today" / "Today's Note" choice shared by every capture surface: Luuna's segmented control. The
/// destination is always explicit.
struct CaptureDestinationPicker: View {
    @Binding var selection: AppModel.CaptureDestination

    var body: some View {
        SegmentedControl(
            "Save as", selection: $selection,
            options: AppModel.CaptureDestination.allCases.map { ($0, $0.title) })
    }
}

extension AppModel.CaptureDestination {
    /// Where a capture lands, for the form's hint. It reports success only after the save reaches disk.
    var hint: String {
        switch self {
        case .task: return "Adds a task due today to your local tasks."
        case .note: return "Appends a list item to today's note in the vault."
        }
    }
}

/// The capture form used by the ⌘N sheet and the floating Capture window: the destination, the field, and a
/// footer with the hint on the left and Capture as the one primary on the right.
struct CaptureForm: View {
    enum Style { case sheet, window }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let style: Style
    @State private var text = ""
    @State private var destination = AppModel.CaptureDestination.task
    @State private var captureError: String?
    @FocusState private var focused: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // The window already shows "Capture" in its title bar.
            if style == .sheet {
                Text("Quick Capture")
                    .textRole(.sectionTitle, lineBox: false)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            LabeledField("Save as") {
                CaptureDestinationPicker(selection: $destination)
            }
            LabeledField("Capture") {
                TextField(
                    "", text: $text, prompt: Text("What's on your mind?").foregroundStyle(Theme.inkMuted),
                    axis: .vertical
                )
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(commit)
                .fieldChrome(focused: focused)
            }
            if let captureError { ReasonNote(captureError, tone: .danger) }
            FormFooter(hint: destination.hint) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Capture", action: commit)
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isEmpty)
            }
        }
        .padding(style == .sheet ? Space.s6 : Space.s5)
        .frame(width: 440)
        .background(Theme.surfaceOverlay)
        .onAppear { focused = true }
    }

    private func commit() {
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
