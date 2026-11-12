import Foundation

extension WorkspaceDirectory {
    /// The association registry: hub ↔ checkouts ↔ optional Luuna project (`AssociationRegistry`).
    public var associationsURL: URL { url.appendingPathComponent("associations.json") }
    /// The Luuna runtime origin (`LuunaHostAccessStore`). Never the token, which stays in the Keychain.
    public var luunaHostURL: URL { url.appendingPathComponent("luuna-host.json") }
}
