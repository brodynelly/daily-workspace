import Foundation

/// A checkout referenced from a hub, as a `file:///…` link or a "Local path: `…`" line.
public struct RepositoryReference: Hashable, Sendable {
    public enum Source: String, Hashable, Sendable {
        case fileLink
        case localPath
    }

    public let source: Source
    /// The link text, when the reference was a Markdown link.
    public let label: String?
    /// Absolute file-system path, percent-decoded.
    public let path: String
    /// 1-based line in the hub file.
    public let line: Int
}

/// A Markdown file in a hub's `notes/` folder.
public struct ProjectNote: Hashable, Sendable {
    /// Vault-relative path.
    public let path: String
    public let modified: Date?

    public var title: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
}

/// Fields from a project-state note shaped like the vault's `templates/project-state.md`.
public struct ProjectState: Hashable, Sendable {
    public struct RestartField: Hashable, Sendable {
        public let key: String
        public let value: String
    }

    /// Vault-relative path of the state note.
    public let path: String
    public let modified: Date?
    public let definitionOfDone: String?
    /// "Current reality" or "Current state".
    public let currentState: String?
    /// "Next executable action" or "Next exact action".
    public let nextAction: String?
    /// "Exact restart" bullets (`File`, `Command`, `Test`…), in order, non-empty values only.
    public let restart: [RestartField]
    public let hypothesis: String?
    public let blockers: [String]
    public let decisions: [String]
}

/// A project hub: a Markdown file under `01-projects/` whose frontmatter says `type: project`.
public struct ProjectHub: Identifiable, Hashable, Sendable {
    public var id: String { path }
    /// The hub file's basename (`daily-workspace` for `01-projects/daily-workspace/daily-workspace.md`).
    public let slug: String
    /// The first H1, else the frontmatter `title`, else the slug.
    public let title: String
    /// Vault-relative path of the hub file.
    public let path: String
    public let tags: [String]
    public let frontmatter: Frontmatter
    /// The first section's prose, bounded.
    public let purpose: String?
    public let repositories: [RepositoryReference]
    /// Bullets of the "Decisions and Unknowns" section, when present.
    public let decisions: [String]
    /// Markdown files in the hub folder's `notes/`, newest first.
    public let notes: [ProjectNote]
    public let modified: Date?
    /// The newest project-state note beside the hub or in `notes/`, when one exists.
    public let state: ProjectState?

    public var latestNoteModified: Date? { notes.compactMap(\.modified).max() }

    /// The key to match Seeds `project:<slug>` labels: the frontmatter `project:` when present, else the slug.
    /// Several hubs can share one (`pi-harness.md` and `brodynelly-brain-project.md` both say `brodynelly-brain`).
    public var projectKey: String { frontmatter.scalars["project"].flatMap { $0.isEmpty ? nil : $0 } ?? slug }

    /// Vault-relative folder that holds the hub file.
    public var folder: String { (path as NSString).deletingLastPathComponent }
}
