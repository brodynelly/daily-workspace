import SwiftUI

/// A live Markdown preview beside the editor, on the muted surface in body ink.
struct NotePreviewView: View {
    let text: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                    Text(
                        (try? AttributedString(markdown: block, options: .init(interpretedSyntax: .full)))
                            ?? AttributedString(block)
                    )
                    .textRole(.body, lineBox: false)
                    .foregroundStyle(Theme.inkBody)
                    .tint(Theme.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
            }
            .padding(Space.s6)
        }
        .background(Theme.surfaceMuted)
        .accessibilityLabel("Markdown preview")
    }
}
