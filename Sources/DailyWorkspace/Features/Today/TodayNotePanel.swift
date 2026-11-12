import DailyCore
import SwiftUI

/// Where today's daily note lives, as the resolver says, and whether it exists yet.
enum TodayNoteLocation: Equatable {
    /// The daily-note settings cannot place today's note (for example no folder is configured).
    case refused(reason: String)
    case resolved(path: String, exists: Bool)

    /// Resolve today's note in the current vault. Reads `.obsidian/daily-notes.json` and checks the file exists;
    /// never creates anything.
    @MainActor
    static func current(in model: AppModel, at date: Date = Date()) -> TodayNoteLocation {
        do {
            let path = try model.resolveDailyNote(for: date).path
            guard let vault = model.vaultSession.vault else { return .refused(reason: "Choose a vault first.") }
            return .resolved(path: path, exists: vault.exists(try vault.resolve(relativePath: path)))
        } catch VaultError.dailyNoteFolderUnset {
            // The resolver's own message is the next step; the panel states the fact and shows that step under it.
            return .refused(reason: "No daily-note folder is set, so today's note has nowhere to go.")
        } catch {
            return .refused(reason: error.localizedDescription)
        }
    }
}

/// The first lines of a note, read-only and plain.
struct TodayNotePreview: Equatable {
    static let lineLimit = 12

    let lines: [String]
    let isTruncated: Bool

    init(text: String, limit: Int = Self.lineLimit) {
        var all = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0.hasSuffix("\r") ? $0.dropLast() : $0)
        }
        while all.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { all.removeLast() }
        lines = Array(all.prefix(limit))
        isTruncated = all.count > limit
    }
}

/// Today's note: its resolved path, a short read-only preview, and Open (or Create when it does not exist yet,
/// through `AppModel.openToday(create:)`). A refusal from the resolver says why and where to fix it.
struct TodayNotePanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var document: NoteDocument

    let location: TodayNoteLocation
    /// Bumped after a capture so a preview read from disk is read again.
    let revision: Int

    @State private var diskPreview: Result<TodayNotePreview, VaultError>?

    var body: some View {
        Panel("Today's note") {
            switch location {
            case .refused(let reason):
                ReasonNote(reason, tone: .attention, next: "Set where daily notes go in Settings → Vault")
            case .resolved(let path, let exists):
                Text(verbatim: path)
                    .font(TextRole.mono.font)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Path \(path)")
                if exists {
                    preview(path: path)
                    Button("Open") { model.openToday(create: false, navigate: true) }
                        .buttonStyle(.primary)
                        .accessibilityLabel("Open today's note")
                } else {
                    Text("Today's note does not exist yet.")
                        .textRole(.bodySmall, lineBox: false)
                        .foregroundStyle(Theme.inkMuted)
                    Button("Create today's note") { model.openToday(create: true, navigate: true) }
                        .buttonStyle(.primary)
                }
            }
        }
        .task(id: diskKey) { loadFromDisk() }
    }

    @ViewBuilder private func preview(path: String) -> some View {
        if document.relativePath == path {
            PreviewBox(preview: TodayNotePreview(text: document.text))
        } else {
            switch diskPreview {
            case .success(let preview): PreviewBox(preview: preview)
            case .failure(let error):
                ReasonNote(error.localizedDescription, tone: .danger)
            case nil: EmptyView()
            }
        }
    }

    /// Re-read from disk when the day's path changes, after a capture, and when the editor lets go of the note.
    private var diskKey: String {
        guard case .resolved(let path, true) = location, document.relativePath != path else { return "" }
        return "\(path)#\(revision)"
    }

    private func loadFromDisk() {
        guard case .resolved(let path, true) = location, document.relativePath != path,
            let vault = model.vaultSession.vault
        else {
            diskPreview = nil
            return
        }
        do {
            let text = try vault.load(try vault.resolve(relativePath: path)).text
            diskPreview = .success(TodayNotePreview(text: text))
        } catch {
            diskPreview = .failure(error as? VaultError ?? .io(error.localizedDescription))
        }
    }
}

/// The preview lines on the muted surface, plain and selectable.
private struct PreviewBox: View {
    let preview: TodayNotePreview

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if preview.lines.isEmpty {
                Text("This note is empty.").foregroundStyle(Theme.inkMuted)
            } else {
                Text(verbatim: preview.lines.joined(separator: "\n"))
                    .foregroundStyle(Theme.inkBody)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if preview.isTruncated {
                    Text("Showing the first \(TodayNotePreview.lineLimit) lines.").foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .textRole(.bodySmall, lineBox: false)
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.surfaceMuted))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of today's note")
    }
}
