import SwiftUI

/// "Task for Today" / "Today's Note" picker shared by every capture surface.
struct CaptureDestinationPicker: View {
    @Binding var selection: AppModel.CaptureDestination

    var body: some View {
        Picker("Save as", selection: $selection) {
            ForEach(AppModel.CaptureDestination.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Save as")
    }
}

/// The capture form used by the ⌘N sheet and the floating Capture window.
struct CaptureForm: View {
    enum Style { case sheet, window }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let style: Style
    @State private var text = ""
    @State private var destination = AppModel.CaptureDestination.task
    @State private var captureError: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The window already shows "Capture" in its title bar.
            if style == .sheet { Text("Quick Capture").font(.headline) }
            TextField("What's on your mind?", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
            CaptureDestinationPicker(selection: $destination)
            if let captureError { Text(captureError).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Capture", action: commit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
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
