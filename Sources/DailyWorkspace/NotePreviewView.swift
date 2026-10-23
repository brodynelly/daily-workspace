import SwiftUI

struct NotePreviewView: View {
    let text: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                    Text((try? AttributedString(markdown: block, options: .init(interpretedSyntax: .full))) ?? AttributedString(block))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
        }
        .accessibilityLabel("Markdown preview")
    }
}
