import SwiftUI

struct QuickCaptureSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var asTask = true
    @State private var captureError: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Capture a thought").font(.system(size: 22, weight: .semibold))
            TextField("What's on your mind?", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(16).softControlSurface()
                .focused($focused)
                .onSubmit(commit)
            Picker("Save as", selection: $asTask) {
                Text("Task for today").tag(true)
                Text("Line in today's note").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Save as")
            if let captureError { Text(captureError).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Capture", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 480)
        .background { WorkspaceCanvas() }
        .onAppear { focused = true }
    }

    private func commit() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if state.capture(text, asTask: asTask) {
            dismiss()
        } else {
            captureError = state.noteMessage ?? "Resolve the open note before capturing."
        }
    }
}
