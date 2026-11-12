import Foundation

// Responses of the first certified Luuna profile: health, project list, project detail and component status.
// Field names follow `packages/api-client/src/index.ts`. Decoding is tolerant: unknown fields are ignored, every
// field the app does not need to identify a record is optional, and enumerated values stay raw strings
// (`LuunaNativeValue`) so a newer runtime's value is shown verbatim instead of failing the whole response.
// Timestamps stay the runtime's strings; `LuunaTimestamp.date(_:)` parses them when a `Date` is needed.
// Native IDs are opaque strings, meaningful only together with the origin that returned them.

/// An enumerated native value kept verbatim, such as an adapter name or a component status.
public struct LuunaNativeValue: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// Parses the runtime's RFC 3339 timestamps, with or without fractional seconds.
public enum LuunaTimestamp {
    public static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// `GET /api/v1/health`. Outside authentication: a healthy runtime proves nothing about the token.
public struct LuunaHealth: Codable, Equatable, Sendable {
    public var status: String
    public var piVersion: String?
    public var piVersionStatus: String?
    /// Approved writers and required checks run with the developer's host permissions.
    public var nativeExecution: Bool?
    /// Content digest of the sources the runtime binary was built from (not a database identity).
    public var buildIdentity: String?
    public var buildRustc: String?
    public var buildRustcSHA256: String?
    public var buildRustcWrapper: String?
    public var buildFlags: String?

    enum CodingKeys: String, CodingKey {
        case status
        case piVersion = "pi_version"
        case piVersionStatus = "pi_version_status"
        case nativeExecution = "native_execution"
        case buildIdentity = "build_identity"
        case buildRustc = "build_rustc"
        case buildRustcSHA256 = "build_rustc_sha256"
        case buildRustcWrapper = "build_rustc_wrapper"
        case buildFlags = "build_flags"
    }
}

/// One element of `GET /api/v1/projects`, and `project` in a project view.
public struct LuunaProjectRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var revision: Int?
    public var manifestHash: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, revision
        case manifestHash = "manifest_hash"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// `GET /api/v1/projects/{id}`.
public struct LuunaProjectView: Codable, Equatable, Sendable {
    public var project: LuunaProjectRecord
    public var repositories: [LuunaRepositoryRegistration]?
    public var manifest: LuunaManifestRecord?
    public var discovery: LuunaDiscoverySummary?
    /// Absent from runtimes that predate the testing-setup prerequisite.
    public var prerequisites: [LuunaTestingPrerequisite]?
}

public struct LuunaRepositoryRegistration: Codable, Equatable, Sendable {
    public var projectID: String?
    public var repositoryID: String
    /// This machine's checkout, as the runtime registered it.
    public var localPath: String?
    public var observation: LuunaRepositoryObservation?
    public var registeredAt: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case repositoryID = "repository_id"
        case localPath = "local_path"
        case observation
        case registeredAt = "registered_at"
    }
}

/// What the runtime saw in a checkout, and when (`observedAt` is the runtime's time, not the app's).
public struct LuunaRepositoryObservation: Codable, Equatable, Sendable {
    public var localPath: String?
    public var identity: LuunaRepositoryIdentity?
    public var headCommit: String?
    public var branch: String?
    public var remoteDefaultBranch: String?
    public var localBranches: [String]?
    public var dirty: LuunaDirtyState?
    public var gitVersion: String?
    public var observedAt: String?

    enum CodingKeys: String, CodingKey {
        case localPath = "local_path"
        case identity
        case headCommit = "head_commit"
        case branch
        case remoteDefaultBranch = "remote_default_branch"
        case localBranches = "local_branches"
        case dirty
        case gitVersion = "git_version"
        case observedAt = "observed_at"
    }
}

public struct LuunaRepositoryIdentity: Codable, Equatable, Sendable {
    public var remote: String?
    public var pushRemote: String?
    public var rootCommits: [String]?
    public var shallow: Bool?

    enum CodingKeys: String, CodingKey {
        case remote
        case pushRemote = "push_remote"
        case rootCommits = "root_commits"
        case shallow
    }
}

public struct LuunaDirtyState: Codable, Equatable, Sendable {
    public var staged: Int?
    public var unstaged: Int?
    public var untracked: Int?
    public var conflicted: Int?
    public var paths: [String]?
    public var truncated: Bool?
}

/// The confirmed manifest revision. Only the parts a read-only panel shows are decoded.
public struct LuunaManifestRecord: Codable, Equatable, Sendable {
    public var projectID: String?
    public var revision: Int?
    public var hash: String?
    public var manifest: LuunaProjectManifest?
    public var baseCommits: [String: String]?
    public var confirmedAt: String?

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case revision, hash, manifest
        case baseCommits = "base_commits"
        case confirmedAt = "confirmed_at"
    }
}

public struct LuunaProjectManifest: Codable, Equatable, Sendable {
    public var schemaVersion: String?
    public var id: String?
    public var name: String?
    public var revision: Int?
    public var repositories: [LuunaRepositoryManifest]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id, name, revision, repositories
    }
}

public struct LuunaRepositoryManifest: Codable, Equatable, Sendable {
    public var id: String
    public var remote: String?
    public var defaultBranch: String?
    public var profiles: [String]?
    /// `native` or `container` today.
    public var execution: LuunaNativeValue?

    enum CodingKeys: String, CodingKey {
        case id, remote
        case defaultBranch = "default_branch"
        case profiles, execution
    }
}

/// A read-only discovery proposal. It authorizes nothing; only its identity and problems are kept.
public struct LuunaDiscoverySummary: Codable, Equatable, Sendable {
    public var id: String?
    public var createdAt: String?
    public var manifestProblems: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case manifestProblems = "manifest_problems"
    }
}

/// The runtime's offer of a testing-setup ticket for a repository; `reason` and `next` are its own words.
public struct LuunaTestingPrerequisite: Codable, Equatable, Sendable {
    public var kind: LuunaNativeValue?
    public var projectID: String?
    public var repositoryID: String?
    public var baselineID: String?
    public var reason: String?
    public var next: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case projectID = "project_id"
        case repositoryID = "repository_id"
        case baselineID = "baseline_id"
        case reason, next
    }
}

/// `GET /api/v1/projects/{id}/components`. `enabled == false` means the project's native components were never
/// activated; the app never enables them.
public struct LuunaComponentStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var workspacePath: String?
    /// The runtime's own reason, such as an unavailable toolchain or an incomplete activation.
    public var reason: String?
    public var adapters: [LuunaComponentAdapterStatus]?

    enum CodingKeys: String, CodingKey {
        case enabled
        case workspacePath = "workspace_path"
        case reason, adapters
    }
}

/// One pinned native adapter, or one per-repository Roots row (which carries `repositoryID`).
public struct LuunaComponentAdapterStatus: Codable, Equatable, Sendable {
    /// `missions`, `atlas`, `beacon`, `roots`, or a newer name.
    public var name: LuunaNativeValue
    public var repositoryID: String?
    public var repositoryPath: String?
    public var backend: String?
    public var backendStatus: LuunaNativeValue?
    public var storeStatus: LuunaNativeValue?
    public var status: LuunaNativeValue?
    public var version: String?
    public var executablePath: String?
    public var sha256: String?
    public var sourceCommit: String?
    public var sourcePath: String?
    public var dataPath: String?
    public var configPath: String?
    public var reason: String?

    enum CodingKeys: String, CodingKey {
        case name
        case repositoryID = "repository_id"
        case repositoryPath = "repository_path"
        case backend
        case backendStatus = "backend_status"
        case storeStatus = "store_status"
        case status, version
        case executablePath = "executable_path"
        case sha256
        case sourceCommit = "source_commit"
        case sourcePath = "source_path"
        case dataPath = "data_path"
        case configPath = "config_path"
        case reason
    }
}
