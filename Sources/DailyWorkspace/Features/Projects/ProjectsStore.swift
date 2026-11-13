import DailyCore
import Foundation

/// One project hub and the app-owned association of other owners' identities to it.
struct ProjectDetail: Equatable {
    let hub: ProjectHub
    let association: ProjectAssociation?
}

/// Project hubs from `01-projects/` and the app-owned association registry. Vault files are read off the
/// main actor and never written; the only file this store writes is `associations.json` in the app folder,
/// through `AssociationRegistry`'s atomic save.
@MainActor
final class ProjectsStore: ObservableObject {
    /// What loading `associations.json` found.
    enum AssociationsStatus: Equatable {
        case notLoaded
        case loaded
        /// The file did not decode and was moved here; associations start empty.
        case movedAside(URL)
        /// The file was written by a newer app version. It is never overwritten, so edits are refused.
        case readOnly(version: Int)
        /// The file exists but could not be read; edits are refused so it is never overwritten blind.
        case unreadable(String)
    }

    /// Hubs sorted by title; nil until the first read finishes.
    @Published private(set) var hubs: SourceObservation<[ProjectHub]>?
    @Published private(set) var selectedSlug: String?
    /// The selected hub and its association; nil without a selection or when the hub is no longer found.
    @Published private(set) var detail: ProjectDetail?
    @Published private(set) var associations: [ProjectAssociation] = []
    @Published private(set) var associationsStatus: AssociationsStatus = .notLoaded
    /// Why the last association edit was refused or failed; cleared by a successful edit.
    @Published private(set) var associationMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var vaultRoot: URL?

    /// Bumped by every refresh and every vault change. A read started under an older value is discarded.
    private(set) var generation = 0

    private let registry: AssociationRegistry
    private let luuna: LuunaStore?
    private let scope: VaultScope
    private let now: () -> Date

    init(
        registry: AssociationRegistry, luuna: LuunaStore?, vaultRoot: URL? = nil, scope: VaultScope = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.registry = registry
        self.luuna = luuna
        self.vaultRoot = vaultRoot
        self.scope = scope
        self.now = now
        loadAssociations()
    }

    /// False while `associations.json` is from a newer app version or unreadable.
    var canEditAssociations: Bool {
        switch associationsStatus {
        case .readOnly, .unreadable: return false
        case .notLoaded, .loaded, .movedAside: return true
        }
    }

    /// The saved association for a hub path, if any.
    func association(forHubPath path: String) -> ProjectAssociation? {
        associations.first { $0.hubPath == path }
    }

    // MARK: Vault and refresh

    /// Read another vault (or none). Its hubs are dropped, the selection is cleared and any read in flight
    /// is discarded. Call `refresh()` afterwards.
    func setVaultRoot(_ root: URL?) {
        guard root?.standardizedFileURL != vaultRoot?.standardizedFileURL else { return }
        vaultRoot = root
        generation += 1
        isRefreshing = false
        hubs = nil
        select(nil)
    }

    /// Re-read hubs off the main actor and reload the association registry. Only the newest refresh for
    /// the current vault publishes; a failed read keeps the previous value as stale.
    func refresh() async {
        generation += 1
        let generation = generation
        isRefreshing = true
        loadAssociations()
        let root = vaultRoot
        let scope = scope
        let date = now()
        let read = await Task.detached(priority: .userInitiated) { () -> SourceObservation<[ProjectHub]>? in
            guard let root else { return nil }
            return ProjectHubReader(root: root, scope: scope).read(now: date)
                .map { $0.sorted(by: Self.titleOrder) }
        }.value
        guard generation == self.generation else {
            Log.app.info("Discarded a projects read for an earlier vault or refresh")
            return
        }
        isRefreshing = false
        guard let read else {
            let state = SourceState.unavailable(reason: "No vault is chosen.")
            hubs = SourceObservation(state: state, value: [], observedAt: date)
            rederive()
            return
        }
        hubs = read.following(hubs)
        rederive()
    }

    // MARK: Selection

    /// Select a hub by slug (nil clears). When its association binds a Luuna project, Luuna shows that project.
    func select(_ slug: String?) {
        selectedSlug = slug
        rederive()
    }

    private func rederive() {
        guard let slug = selectedSlug, let hub = hubs?.value.first(where: { $0.slug == slug }) else {
            detail = nil
            bindSelectedLuunaProject(nil)
            return
        }
        let association = association(forHubPath: hub.path)
        detail = Self.detail(for: hub, association: association)
        bindSelectedLuunaProject(association?.luuna)
    }

    private func bindSelectedLuunaProject(_ binding: LuunaProjectBinding?) {
        guard let luuna, luuna.selectedProject != binding else { return }
        luuna.selectProject(binding)
        if binding != nil { Task { await luuna.refresh() } }
    }

    static func detail(for hub: ProjectHub, association: ProjectAssociation? = nil) -> ProjectDetail {
        ProjectDetail(hub: hub, association: association)
    }

    private nonisolated static func titleOrder(_ lhs: ProjectHub, _ rhs: ProjectHub) -> Bool {
        switch lhs.title.localizedStandardCompare(rhs.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.path < rhs.path
        }
    }

    // MARK: Associations (app-owned)

    /// Add a checkout path (absolute, `~` expanded) to the selected hub's association, creating the association
    /// when needed. Returns why it was refused, or nil once saved.
    @discardableResult
    func addCheckout(path: String, label: String? = nil) -> String? {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return refuse("Enter the checkout's full path, such as ~/github/app.") }
        let normalized = (expanded as NSString).standardizingPath
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return edit { association in
            guard !association.checkouts.contains(where: { $0.path == normalized }) else { return }
            association.checkouts.append(
                RepositoryCheckoutReference(
                    path: normalized, label: trimmedLabel?.isEmpty == false ? trimmedLabel : nil))
        }
    }

    /// Remove a checkout path from the selected hub's association.
    @discardableResult
    func removeCheckout(path: String) -> String? {
        edit { $0.checkouts.removeAll { $0.path == path } }
    }

    /// Bind the selected hub to a Luuna project on `origin`. The ID means nothing without its origin.
    @discardableResult
    func bindLuuna(origin: LuunaOrigin, projectID: String) -> String? {
        let id = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return refuse("Enter the Luuna project ID.") }
        return edit { $0.luuna = LuunaProjectBinding(origin: origin, projectID: id) }
    }

    @discardableResult
    func unbindLuuna() -> String? {
        edit { $0.luuna = nil }
    }

    /// Applies `change` to the selected hub's association and saves the whole registry atomically. An association
    /// left with no checkouts and no binding is removed. Nothing changes in memory unless the save succeeded.
    private func edit(_ change: (inout ProjectAssociation) -> Void) -> String? {
        guard let hub = detail?.hub else { return refuse("Select a project first.") }
        if let reason = readOnlyReason { return refuse(reason) }
        var next = associations
        let index = next.firstIndex { $0.hubPath == hub.path }
        var association = index.map { next[$0] } ?? ProjectAssociation(hubPath: hub.path)
        change(&association)
        let isEmpty = association.checkouts.isEmpty && association.luuna == nil
        switch (index, isEmpty) {
        case (let index?, true): next.remove(at: index)
        case (let index?, false): next[index] = association
        case (nil, false): next.append(association)
        case (nil, true): break
        }
        guard next != associations else {
            associationMessage = nil
            return nil
        }
        do {
            try registry.save(next)
        } catch AssociationRegistryError.newerVersion(let version) {
            associationsStatus = .readOnly(version: version)
            return refuse(readOnlyReason ?? "")
        } catch {
            Log.app.error(
                "Associations could not be saved: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            return refuse("The association could not be saved: \(error.localizedDescription)")
        }
        associations = next
        associationMessage = nil
        rederive()
        return nil
    }

    private var readOnlyReason: String? {
        switch associationsStatus {
        case .readOnly(let version):
            return
                "associations.json was written by a newer version of Daily Workspace (format \(version)). "
                + "It is read-only here and is never overwritten."
        case .unreadable(let reason):
            return "associations.json could not be read, so it is not changed: \(reason)"
        case .notLoaded, .loaded, .movedAside:
            return nil
        }
    }

    private func refuse(_ reason: String) -> String {
        associationMessage = reason
        return reason
    }

    private func loadAssociations() {
        do {
            let load = try registry.load()
            associations = load.value
            if let aside = load.movedAside {
                Log.app.notice("associations.json did not decode and was moved aside")
                associationsStatus = .movedAside(aside)
            } else if case .movedAside = associationsStatus {
                // Keep reporting where the unreadable file went until the app restarts.
            } else {
                associationsStatus = .loaded
            }
        } catch AssociationRegistryError.newerVersion(let version) {
            associations = []
            associationsStatus = .readOnly(version: version)
        } catch {
            Log.app.error(
                "Associations could not be read: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            associationsStatus = .unreadable(error.localizedDescription)
        }
    }

}
