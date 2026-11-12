import AppKit
import SwiftUI

/// Shown while saving is paused because the note changed on disk.
struct ConflictBanner: View {
    @EnvironmentObject private var document: NoteDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This note changed outside the app", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(
                "Saving is paused so nothing is overwritten. Whichever version you don't keep is saved to a recovery folder."
            )
            .font(.callout)
            if let message = document.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Reload From Disk") { document.resolveConflictByReloading() }
                Button("Keep My Version") { document.resolveConflictByKeepingMine() }
                if let folder = document.recoveryFolder {
                    Button("Show Recovery Folder") { NSWorkspace.shared.open(folder) }
                        .buttonStyle(.link)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}
