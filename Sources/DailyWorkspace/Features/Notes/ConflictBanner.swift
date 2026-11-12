import AppKit
import SwiftUI

/// Shown while saving is paused because the note changed on disk: an attention callout with the reason, the
/// next step ruled in the accent, then the ways out. Neither version is the primary: which to keep is
/// Brody's call. The actions sit outside the callout so each stays its own control for VoiceOver.
struct ConflictBanner: View {
    @EnvironmentObject private var document: NoteDocument

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Callout(tone: .attention) {
                Text("This note changed outside the app")
                    .textRole(.label, lineBox: false)
                    .foregroundStyle(Theme.ink)
                Text("Saving is paused so nothing is overwritten.")
                    .fixedSize(horizontal: false, vertical: true)
                if let message = document.message {
                    Text(message).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            NextStepNote(
                "Reload the note from disk, or keep your version. The one you don't keep is saved to a recovery folder."
            )
            HStack(spacing: Space.s2) {
                Button("Reload From Disk") { document.resolveConflictByReloading() }
                    .buttonStyle(.secondary)
                Button("Keep My Version") { document.resolveConflictByKeepingMine() }
                    .buttonStyle(.secondary)
                if let folder = document.recoveryFolder {
                    Button("Show Recovery Folder") { NSWorkspace.shared.open(folder) }
                        .buttonStyle(.text)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note changed outside the app")
    }
}
