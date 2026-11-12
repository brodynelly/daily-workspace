import SwiftUI

struct SaveStatusLabel: View {
    let state: NoteDocument.SaveState

    var body: some View {
        switch state {
        case .clean: Label("Saved", systemImage: "checkmark.circle")
        case .dirty: Label("Unsaved changes", systemImage: "circle.dotted")
        case .saving: Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
        case .conflict: Label("Conflict: not saved", systemImage: "exclamationmark.triangle.fill")
        case .failed(let why): Label("Save failed: \(why)", systemImage: "xmark.octagon.fill")
        }
    }
}
