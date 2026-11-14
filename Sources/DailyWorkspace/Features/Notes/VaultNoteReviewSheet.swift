import DailyCore
import SwiftUI

/// A deterministic, individually confirmed vault change. The Assistant supplies draft text and citations,
/// never a destination, permission, or write action. A new preview is mandatory after editing or conflict.
struct VaultNoteReviewSheet: View {
    enum Source {
        case quickNotes
        case inbox
        case assistant(paths: [String])
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let source: Source
    let onDraftChange: (String) -> Void
    let onSaved: () -> Void
    @State private var path: String
    @State private var draft: String
    @State private var replaceExisting = false
    @State private var review: VaultNoteReview?
    @State private var error: String?

    init(
        source: Source, draft: String, onDraftChange: @escaping (String) -> Void = { _ in },
        onSaved: @escaping () -> Void = {}
    ) {
        self.source = source
        self.onDraftChange = onDraftChange
        self.onSaved = onSaved
        let initialPath: String
        switch source {
        case .quickNotes: initialPath = VaultNoteReview.quickNotesPath
        case .inbox: initialPath = "00-inbox/"
        case .assistant: initialPath = ""
        }
        _path = State(initialValue: initialPath)
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Review vault note").textRole(.sectionTitle, lineBox: false)
            Text("Only your final confirmation saves this exact change in the selected Obsidian vault.")
                .textRole(.bodySmall, lineBox: false)
            if case .assistant(let paths) = source {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Source paths returned by Assistant tools").textRole(.label, lineBox: false)
                    ForEach(paths, id: \.self) { Text(verbatim: $0).textRole(.caption, lineBox: false) }
                }
            }
            if case .quickNotes = source {
                Text(verbatim: path).textRole(.bodySmall, lineBox: false).textSelection(.enabled)
            } else {
                TextField("Exact vault-relative Markdown path", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Exact vault-relative Markdown path")
                    .onChange(of: path) { _, _ in invalidate() }
            }
            if review == nil {
                Text("Draft (edit before preview)").textRole(.label, lineBox: false)
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 110, maxHeight: 170)
                    .border(Theme.border)
                    .accessibilityLabel("Note draft")
                if case .assistant = source {
                    Toggle("Replace the whole existing note instead of appending", isOn: $replaceExisting)
                        .onChange(of: replaceExisting) { _, _ in invalidate() }
                }
            } else if let review {
                Text(verbatim: review.path).textRole(.label, lineBox: false).textSelection(.enabled)
                HStack(alignment: .top, spacing: Space.s3) {
                    preview("Before", text: review.before ?? "New note — no existing text")
                    preview("After", text: review.after)
                }
            }
            if let error { ReasonNote(error, tone: .danger) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(.secondary)
                Spacer()
                if review != nil {
                    Button("Edit draft", action: invalidate).buttonStyle(.secondary)
                    Button("Confirm save", action: commit).buttonStyle(.primary)
                } else {
                    Button("Preview exact change", action: prepare).buttonStyle(.primary)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(Space.s5)
        .frame(width: 720)
        .background(Theme.surfaceOverlay)
        .onChange(of: draft) { _, updated in
            invalidate()
            onDraftChange(updated)
        }
    }

    private func preview(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label).textRole(.label, lineBox: false)
            ScrollView {
                Text(verbatim: text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: 200)
            .padding(Space.s2)
            .background(Theme.surfaceRaised)
        }
        .frame(maxWidth: .infinity)
    }

    private func invalidate() {
        review = nil
        error = nil
    }

    private func prepare() {
        do {
            let mode: VaultNoteReview.Mode
            let requirement: VaultNoteReview.Requirement
            switch source {
            case .quickNotes:
                mode = .quickNotes
                requirement = .existing
            case .inbox:
                guard path.hasPrefix("00-inbox/"),
                    !path.dropFirst("00-inbox/".count).contains("/"), path.hasSuffix(".md")
                else { throw VaultError.io("Name a new Markdown note directly in 00-inbox/.") }
                mode = .replace
                requirement = .new
            case .assistant(let paths):
                guard !paths.isEmpty else { throw VaultError.io("Ask the Assistant to look up a note first.") }
                mode = replaceExisting ? .replace : .append
                requirement = .either
            }
            review = try VaultNoteReview.prepare(
                model: model, path: path, draft: draft, mode: mode, requirement: requirement)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func commit() {
        guard let review else { return }
        do {
            try review.commit(model: model)
            error = nil
            onSaved()
            dismiss()
        } catch {
            self.review = nil
            self.error = "The note was not saved: \(error.localizedDescription) Reopen the preview before retrying."
        }
    }
}
