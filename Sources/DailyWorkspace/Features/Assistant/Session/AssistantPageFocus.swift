import DailyCore
import Foundation

/// Navigation metadata for an explicit Ask, not a snapshot of source content or evidence.
@MainActor
struct AssistantPageFocus {
    let title: String
    let detail: String?
    let contextText: String

    static func current(section: AppSection, model: AppModel) -> AssistantPageFocus {
        let detail: String?
        let hint: String
        switch section {
        case .today:
            detail = nil
            hint = "Explore today's workspace agenda and note."
        case .projects:
            detail = selectedProject(in: model).flatMap { quoted($0).map { "Project slug: \($0)" } }
            hint = "Explore project hubs in the selected vault."
        case .openLoops:
            detail = nil
            hint = "Explore open loops through available read-only sources."
        case .notes:
            detail = selectedNote(in: model).flatMap { quoted($0).map { "Note path: \($0)" } }
            hint = "Explore notes in the selected vault."
        case .calendar:
            detail = "Selected day: \(LocalDay(model.calendar.selectedDay).description)"
            hint = "Explore the selected day's calendar."
        case .assistant:
            detail = nil
            hint = "Explore the workspace through read-only tools."
        }

        var text = "Page focus (navigation metadata, not evidence):\nSection: \(section.title)\n"
        if let detail { text += "\(detail)\n" }
        text +=
            "\(hint)\nUse read-only tools to verify claims and citations; this metadata is not source evidence. "
            + "Unavailable sources are unknown, not empty."
        return AssistantPageFocus(title: section.title, detail: detail, contextText: text)
    }

    /// Vault filenames are untrusted data. Escape controls before embedding them in a model-facing block.
    private static func quoted(_ value: String) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func selectedProject(in model: AppModel) -> String? {
        guard let root = model.vaultSession.vault?.root,
            root.standardizedFileURL == model.projects.vaultRoot?.standardizedFileURL,
            let hubs = model.projects.hubs, hubs.state.isReadable,
            let detail = model.projects.detail,
            detail.hub.slug == model.projects.selectedSlug,
            let allowed = try? VaultReadPolicy.resolve(detail.hub.path, root: root, scope: .standard),
            allowed.path == detail.hub.path,
            FileManager.default.fileExists(atPath: allowed.url.path)
        else { return nil }
        return detail.hub.slug
    }

    private static func selectedNote(in model: AppModel) -> String? {
        guard let root = model.vaultSession.vault?.root,
            model.document.vault?.root.standardizedFileURL == root.standardizedFileURL,
            let path = model.document.relativePath,
            let allowed = try? VaultReadPolicy.resolve(path, root: root, scope: .standard),
            VaultReadPolicy.noteExtensions.contains(allowed.url.pathExtension.lowercased()),
            FileManager.default.fileExists(atPath: allowed.url.path)
        else { return nil }
        return allowed.path
    }
}
