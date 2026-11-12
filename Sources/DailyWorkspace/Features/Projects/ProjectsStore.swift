import DailyCore
import Foundation

/// One project hub with what other owners say about it. Every part keeps its owner: Seeds records carry their own
/// status, Plot records their own, and the association is the app's own record of what belongs together.
struct ProjectDetail: Equatable {
    let hub: ProjectHub
    /// Seeds issues labelled `project:<hub.projectKey>`, in Seeds order.
    let issues: [SeedsRecord]
    /// Seeds plans for the project: their own `project:` label, else their seed issue's.
    let plans: [SeedsRecord]
    /// Plots that attach one of `issues`, a file in the hub's folder, or `project:<hub.projectKey>`.
    let plots: [PlotRecord]
    /// The state of the Seeds and Plot reads these rows came from (nil before the first read).
    let seedsState: SourceState?
    let plotState: SourceState?
    /// The app-owned association for this hub, if one was saved.
    let association: ProjectAssociation?
}

/// Project hubs from `01-projects/`, the selected hub's Seeds and Plot rows, and the app-owned association
/// registry. Vault files are read off the main actor and never written; the only file this store writes is
/// `associations.json` in the app folder, through `AssociationRegistry`'s atomic save.
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
    @Published private(set) var seeds: SourceObservation<SeedsSnapshot>?
    @Published private(set) var plots: SourceObservation<[PlotRecord]>?
    @Published private(set) var selectedSlug: String?
    /// The selected hub and its derived rows; nil without a selection or when the hub is not (or no longer) found.
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

    /// Read another vault (or none). Its hubs, Seeds and Plot reads are dropped, the selection is cleared and
    /// any read in flight is discarded. Call `refresh()` afterwards.
    func setVaultRoot(_ root: URL?) {
        guard root?.standardizedFileURL != vaultRoot?.standardizedFileURL else { return }
        vaultRoot = root
        generation += 1
        isRefreshing = false
        hubs = nil
        seeds = nil
        plots = nil
        select(nil)
    }

    /// Re-reads hubs, Seeds and Plot off the main actor and reloads the association registry. Only the newest
    /// refresh for the current vault publishes; a failed read keeps the previous value as stale.
    func refresh() async {
        generation += 1
        let generation = generation
        isRefreshing = true
        loadAssociations()
        let root = vaultRoot
        let scope = scope
        let date = now()
        let read = await Task.detached(priority: .userInitiated) { () -> VaultRead? in
            guard let root else { return nil }
            let hubs = ProjectHubReader(root: root, scope: scope).read(now: date)
            return VaultRead(
                hubs: hubs.map { $0.sorted(by: Self.titleOrder) },
                seeds: SeedsReader(root: root).readSnapshot(now: date),
                plots: PlotReader(root: root).readPlots(now: date))
        }.value
        guard generation == self.generation else {
            Log.app.info("Discarded a projects read for an earlier vault or refresh")
            return
        }
        isRefreshing = false
        guard let read else {
            let state = SourceState.unavailable(reason: "No vault is chosen.")
            hubs = SourceObservation(state: state, value: [], observedAt: date)
            seeds = SourceObservation(state: state, value: SeedsSnapshot(), observedAt: date)
            plots = SourceObservation(state: state, value: [], observedAt: date)
            rederive()
            return
        }
        hubs = read.hubs.following(hubs)
        seeds = read.seeds.following(seeds)
        plots = read.plots.following(plots)
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
        detail = Self.detail(
            for: hub, seeds: seeds?.value ?? SeedsSnapshot(), plots: plots?.value ?? [], seedsState: seeds?.state,
            plotState: plots?.state, association: association)
        bindSelectedLuunaProject(association?.luuna)
    }

    private func bindSelectedLuunaProject(_ binding: LuunaProjectBinding?) {
        guard let luuna, luuna.selectedProject != binding else { return }
        luuna.selectProject(binding)
        if binding != nil { Task { await luuna.refresh() } }
    }

    /// The hub's Seeds issues and plans (matched on `projectKey`) and the Plots that refer to them or the project.
    static func detail(
        for hub: ProjectHub, seeds: SeedsSnapshot, plots: [PlotRecord], seedsState: SourceState? = nil,
        plotState: SourceState? = nil, association: ProjectAssociation? = nil
    ) -> ProjectDetail {
        let key = hub.projectKey
        let issues = seeds.issues.filter { $0.project == key }
        let issueProjects = Dictionary(seeds.issues.map { ($0.id, $0.project) }, uniquingKeysWith: { _, last in last })
        let plans = seeds.plans.filter { plan in
            (plan.project ?? plan.extra["seed"]?.stringValue.flatMap { issueProjects[$0] ?? nil }) == key
        }
        let issueIDs = Set(issues.map(\.id))
        let folder = hub.folder + "/"
        let relatedPlots = plots.filter { plot in
            plot.references.contains { reference in
                (reference.isSeedsIssue && issueIDs.contains(reference.ref))
                    || (reference.isFile && (reference.ref == hub.path || reference.ref.hasPrefix(folder)))
                    || reference.ref == "project:\(key)"
            }
        }
        return ProjectDetail(
            hub: hub, issues: issues, plans: plans, plots: relatedPlots, seedsState: seedsState, plotState: plotState,
            association: association)
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

    private struct VaultRead: Sendable {
        let hubs: SourceObservation<[ProjectHub]>
        let seeds: SourceObservation<SeedsSnapshot>
        let plots: SourceObservation<[PlotRecord]>
    }
}
