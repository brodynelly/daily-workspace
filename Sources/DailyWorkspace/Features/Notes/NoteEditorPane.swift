import SwiftUI

/// The open note: the conflict callout or a status message, then the editor (and the preview beside it) on
/// a raised surface, with a quiet meta line under it: the note's path, its length and its save status.
struct NoteEditorPane: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var document: NoteDocument

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if document.isConflict {
                ConflictBanner()
            } else if let message = document.message {
                Callout(message)
            }
            VStack(spacing: 0) {
                HSplitView {
                    MarkdownEditor(
                        text: Binding(get: { document.text }, set: { document.userEdited($0) }),
                        documentID: document.url,
                        preset: preferences.caretPreset,
                        reduceMotion: model.systemReduceMotion
                    )
                    .frame(minWidth: 280)
                    if preferences.showNotePreview {
                        NotePreviewView(text: document.text).frame(minWidth: 220)
                    }
                }
                Hairline()
                metaLine
            }
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: Metrics.borderWidth)
            }
        }
    }

    /// A muted evidence line: the path whole in monospace (it wraps, never truncates), tabular figures.
    private var metaLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Text(verbatim: document.relativePath ?? "")
                .font(.system(size: TextRole.caption.size, design: .monospaced))
                .foregroundStyle(Theme.inkBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(document.text.count) characters")
                .monospacedDigit()
                .fixedSize()
            SaveStatusLabel(state: document.saveState)
        }
        .textRole(.caption, lineBox: false)
        .foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(Theme.surfaceMuted)
    }
}
