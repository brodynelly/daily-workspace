import Foundation

public enum AssociationRegistryError: Error, Equatable {
    /// A hub path that is absolute or could leave the vault.
    case invalidHubPath(String)
    /// Two associations share one ID.
    case duplicateID(UUID)
    /// The file was written by a newer version of the app. It is left untouched and never overwritten.
    case newerVersion(Int)
}

/// What loading an app-owned file found.
public struct AppFileLoad<Value> {
    public let value: Value
    /// Where an unreadable (corrupt) file was moved before an empty value was returned, if that happened.
    public let movedAside: URL?
}

extension AppFileLoad: Equatable where Value: Equatable {}

/// The association registry, `associations.json` in the app folder: which hub, checkouts and Luuna project belong
/// together. Saves are atomic. A file that does not decode is moved aside to `associations.corrupt-<time>.json`,
/// never overwritten; a file from a newer app version is refused, never overwritten.
public struct AssociationRegistry {
    public static let currentVersion = 1

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(directory: WorkspaceDirectory) {
        self.init(url: directory.associationsURL)
    }

    /// The saved associations; empty when there is no file yet or a corrupt one was moved aside.
    public func load() throws -> AppFileLoad<[ProjectAssociation]> {
        let file = AppOwnedJSONFile(url: url)
        let (document, movedAside) = try file.read(Document.self)
        guard let document else { return AppFileLoad(value: [], movedAside: movedAside) }
        guard document.version <= Self.currentVersion else {
            throw AssociationRegistryError.newerVersion(document.version)
        }
        return AppFileLoad(value: document.associations, movedAside: movedAside)
    }

    /// Replaces the file atomically. Refuses invalid hub paths, duplicate IDs and a newer file on disk; a corrupt
    /// file on disk is moved aside first.
    public func save(_ associations: [ProjectAssociation]) throws {
        var seen = Set<UUID>()
        for association in associations {
            guard ProjectAssociation.isVaultRelative(association.hubPath) else {
                throw AssociationRegistryError.invalidHubPath(association.hubPath)
            }
            guard seen.insert(association.id).inserted else {
                throw AssociationRegistryError.duplicateID(association.id)
            }
        }
        let file = AppOwnedJSONFile(url: url)
        if let existing = try file.peekVersion(), existing > Self.currentVersion {
            throw AssociationRegistryError.newerVersion(existing)
        }
        try file.write(Document(version: Self.currentVersion, associations: associations))
    }

    private struct Document: Codable {
        var version: Int
        var associations: [ProjectAssociation]

        init(version: Int, associations: [ProjectAssociation]) {
            self.version = version
            self.associations = associations
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            associations = try container.decodeIfPresent([ProjectAssociation].self, forKey: .associations) ?? []
        }
    }
}

/// `luuna-host.json` in the app folder: the runtime origin only. The token stays in the Keychain.
public struct LuunaHostAccessStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(directory: WorkspaceDirectory) {
        self.init(url: directory.luunaHostURL)
    }

    /// The saved access, or nil when none is saved (or a corrupt file was moved aside).
    public func load() throws -> AppFileLoad<LuunaHostAccess?> {
        let (access, movedAside) = try AppOwnedJSONFile(url: url).read(LuunaHostAccess.self)
        return AppFileLoad(value: access, movedAside: movedAside)
    }

    public func save(_ access: LuunaHostAccess) throws {
        try AppOwnedJSONFile(url: url).write(access)
    }
}

/// Shared rules for the app's small JSON files: atomic, user-only writes, and a corrupt file moved aside rather
/// than overwritten. A file that cannot be read at all (permissions, I/O) throws instead.
struct AppOwnedJSONFile {
    let url: URL

    func read<Value: Decodable>(_ type: Value.Type) throws -> (Value?, movedAside: URL?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil) }
        let data = try Data(contentsOf: url)
        if let value = try? JSONDecoder().decode(Value.self, from: data) { return (value, nil) }
        return (nil, try moveAside())
    }

    /// The `version` field of the JSON object on disk (1 when absent), or nil when there is no file or it is not
    /// a JSON object.
    func peekVersion() throws -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["version"] as? Int ?? 1
    }

    /// Writes `value` atomically, readable only by this user. A file already on disk that does not decode as
    /// `Value` is moved aside first, so a corrupt file is never overwritten.
    func write<Value: Codable>(_ value: Value) throws {
        let folder = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            if (try? JSONDecoder().decode(Value.self, from: existing)) == nil { try moveAside() }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Renames the file to `<name>.corrupt-<time>[-n].json` and returns the new location. Throws (leaving the
    /// file in place) if it cannot be renamed.
    @discardableResult
    func moveAside() throws -> URL {
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let time = Int(Date().timeIntervalSince1970)
        var aside = folder.appendingPathComponent("\(stem).corrupt-\(time).json")
        var attempt = 1
        while FileManager.default.fileExists(atPath: aside.path) {
            attempt += 1
            aside = folder.appendingPathComponent("\(stem).corrupt-\(time)-\(attempt).json")
        }
        try FileManager.default.moveItem(at: url, to: aside)
        return aside
    }
}
