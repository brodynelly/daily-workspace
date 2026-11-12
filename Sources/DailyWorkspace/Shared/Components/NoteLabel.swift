import SwiftUI

/// How a vault-relative note path is shown: title first, folder dimmed, so `a/index.md` and
/// `b/index.md` stay distinguishable everywhere.
enum NotePath {
    static func title(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// Containing folder, or nil at the vault root.
    static func folder(_ path: String) -> String? {
        let folder = (path as NSString).deletingLastPathComponent
        return folder.isEmpty ? nil : folder
    }

    /// Single-line form for menus: "index — projects/alpha".
    static func menuTitle(_ path: String) -> String {
        folder(path).map { "\(title(path)) — \($0)" } ?? title(path)
    }
}

struct NoteLabel: View {
    let path: String
    var icon: String?

    var body: some View {
        let content = HStack(spacing: 6) {
            Text(NotePath.title(path)).lineLimit(1)
            if let folder = NotePath.folder(path) {
                Text(folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
        }
        if let icon {
            Label {
                content
            } icon: {
                Image(systemName: icon)
            }
            .help(path)
        } else {
            content.help(path)
        }
    }
}
