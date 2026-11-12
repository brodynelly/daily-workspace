import Foundation

/// One repository checkout a project hub refers to.
public struct RepositoryCheckoutReference: Codable, Hashable, Sendable {
    /// The checkout's path on this Mac.
    public var path: String
    /// An optional name to show instead of the path.
    public var label: String?

    public init(path: String, label: String? = nil) {
        self.path = path
        self.label = label
    }
}

/// An explicit binding to a Luuna project: the runtime origin that owns the ID, plus the ID. The ID means nothing
/// without its origin; a name, an equal HEAD commit or a reused port never establishes a binding.
public struct LuunaProjectBinding: Codable, Hashable, Sendable {
    public var origin: LuunaOrigin
    public var projectID: String

    public init(origin: LuunaOrigin, projectID: String) {
        self.origin = origin
        self.projectID = projectID
    }

    enum CodingKeys: String, CodingKey {
        case origin
        case projectID = "project_id"
    }
}

/// What the user said belongs together: a project hub in the vault, any number of repository checkouts, and an
/// optional Luuna project. App-owned state; it copies nothing from the hub, the repositories or Luuna.
public struct ProjectAssociation: Codable, Hashable, Sendable, Identifiable {
    /// The app's own ID for this association, stable across hub moves and repairs.
    public var id: UUID
    /// The hub note's path relative to the vault root, such as `01-projects/daily-workspace/daily-workspace.md`.
    public var hubPath: String
    public var checkouts: [RepositoryCheckoutReference]
    public var luuna: LuunaProjectBinding?

    public init(
        id: UUID = UUID(), hubPath: String, checkouts: [RepositoryCheckoutReference] = [],
        luuna: LuunaProjectBinding? = nil
    ) {
        self.id = id
        self.hubPath = hubPath
        self.checkouts = checkouts
        self.luuna = luuna
    }

    enum CodingKeys: String, CodingKey {
        case id
        case hubPath = "hub_path"
        case checkouts, luuna
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hubPath = try container.decode(String.self, forKey: .hubPath)
        checkouts = try container.decodeIfPresent([RepositoryCheckoutReference].self, forKey: .checkouts) ?? []
        luuna = try container.decodeIfPresent(LuunaProjectBinding.self, forKey: .luuna)
    }

    /// True when `path` is a non-empty, vault-relative path that cannot leave the vault: no leading `/` or `~`,
    /// no `.` or `..` segments and no empty segments.
    public static func isVaultRelative(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\\") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}

/// How the app reaches a Luuna runtime on this Mac: the origin only. The bearer token lives in the Keychain and is
/// never written to a file; this type has no field that could hold it.
public struct LuunaHostAccess: Codable, Equatable, Sendable {
    public var origin: LuunaOrigin

    public init(origin: LuunaOrigin = .standard) {
        self.origin = origin
    }
}
