import AppKit
import DailyCore
import SwiftUI

/// The hub's repository references (from its own Markdown) and the checkouts the user associated with it. Each
/// path is shown whole in monospace. Adding or removing a checkout changes only the app's `associations.json`,
/// through `ProjectsStore`; the hub and the repositories are never touched.
struct ProjectRepositoriesPanel: View {
    let detail: ProjectDetail

    @EnvironmentObject private var projects: ProjectsStore
    @State private var newPath = ""
    @State private var message: String?

    var body: some View {
        Panel(
            "Repositories",
            description:
                "Checkouts on this Mac. Adding or removing one changes only associations.json in the app folder.",
            variant: .subpanel
        ) {
            associationNotice
            let references = detail.hub.repositories
            let checkouts = detail.association?.checkouts ?? []
            if references.isEmpty, checkouts.isEmpty {
                Text("The hub references no repository, and no checkout is associated yet.")
                    .textRole(.bodySmall, lineBox: false)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                RecordList(variant: .rows) {
                    ForEach(Array(references.enumerated()), id: \.offset) { _, reference in
                        PathRecord(path: reference.path, label: reference.label, origin: "Hub line \(reference.line)")
                    }
                    ForEach(checkouts, id: \.path) { checkout in
                        PathRecord(path: checkout.path, label: checkout.label, origin: "Associated checkout") {
                            Button("Remove") { message = projects.removeCheckout(path: checkout.path) }
                                .buttonStyle(.workspace(.quiet, size: .small))
                                .disabled(!projects.canEditAssociations)
                        }
                    }
                }
            }
            HStack(spacing: Space.s2) {
                BoxedTextField("~/github/project", text: $newPath, monospaced: true, onSubmit: add)
                Button("Add checkout", action: add)
                    .buttonStyle(.secondary)
                    .disabled(!projects.canEditAssociations || newPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .disabled(!projects.canEditAssociations)
            if let message { ReasonNote(message, tone: .danger) }
        }
    }

    private func add() {
        message = projects.addCheckout(path: newPath)
        if message == nil { newPath = "" }
    }

    @ViewBuilder private var associationNotice: some View {
        switch projects.associationsStatus {
        case .movedAside(let url):
            Callout(
                "associations.json could not be read and was moved to \(url.path). Associations start empty.",
                tone: .attention)
        case .readOnly(let version):
            Callout(
                "associations.json was written by a newer version of Daily Workspace (format \(version)). "
                    + "It is read-only here and is never overwritten.", tone: .attention)
        case .unreadable(let reason):
            Callout("associations.json could not be read, so it is not changed: \(reason)", tone: .danger)
        case .notLoaded, .loaded:
            EmptyView()
        }
    }
}

/// One path: its label and where it came from, the path whole in monospace, then Reveal in Finder and Copy path.
/// Revealing reads the file system only.
struct PathRecord<Extra: View>: View {
    let path: String
    var label: String?
    let origin: String
    @ViewBuilder var extra: Extra

    @State private var notice: String?

    init(path: String, label: String?, origin: String, @ViewBuilder extra: () -> Extra) {
        self.path = path
        self.label = label
        self.origin = origin
        self.extra = extra()
    }

    var body: some View {
        RecordRow {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(spacing: Space.s2) {
                        if let label, !label.isEmpty {
                            Text(verbatim: label).textRole(.body, lineBox: false).foregroundStyle(Theme.ink)
                        }
                        Tag(origin)
                    }
                    Text(verbatim: path)
                        .font(TextRole.mono.font)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notice {
                        Text(notice).textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Space.s1) {
                    Button("Reveal in Finder", action: reveal).buttonStyle(.workspace(.secondary, size: .small))
                    Button("Copy path", action: copy).buttonStyle(.workspace(.secondary, size: .small))
                    extra
                }
            }
        }
    }

    private func reveal() {
        notice =
            FileManager.default.fileExists(atPath: path)
                && NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            ? nil : "Not found on this Mac."
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        notice = "Copied."
    }
}

extension PathRecord where Extra == EmptyView {
    init(path: String, label: String?, origin: String) {
        self.init(path: path, label: label, origin: origin) { EmptyView() }
    }
}
