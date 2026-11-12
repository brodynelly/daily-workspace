import SwiftUI

/// The open note's save state as a quiet meta: the tone's mark and the words. "Saved" means the bytes are on
/// disk; it is a record, not evidence, so it is never green.
struct SaveStatusLabel: View {
    let state: NoteDocument.SaveState

    var body: some View {
        HStack(spacing: Space.s1Half) {
            ToneMark(tone: tone)
            Text(text)
                .foregroundStyle(tone == .danger || tone == .attention ? tone.foreground : Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textRole(.caption, lineBox: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var text: String {
        switch state {
        case .clean: return "Saved"
        case .dirty: return "Unsaved changes"
        case .saving: return "Saving…"
        case .conflict: return "Conflict: not saved"
        case .failed(let why): return "Save failed: \(why)"
        }
    }

    private var tone: Tone {
        switch state {
        case .clean, .dirty: return .neutral
        case .saving: return .active
        case .conflict: return .attention
        case .failed: return .danger
        }
    }
}
