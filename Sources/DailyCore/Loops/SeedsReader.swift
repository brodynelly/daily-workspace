import Foundation

/// One Seeds issue or plan, as stored in `.seeds/issues.jsonl` or `.seeds/plans.jsonl`.
public struct SeedsRecord: Hashable, Sendable {
    public enum Store: String, Hashable, Sendable {
        case issues
        case plans

        public var path: String { ".seeds/\(rawValue).jsonl" }
    }

    public let store: Store
    public let id: String
    /// `title` for issues; plans store `name`.
    public let title: String?
    /// Verbatim (`open`, `in_progress`, `closed`; plans `draft`, `approved`, `active`, `done`).
    public let status: String?
    public let type: String?
    public let priority: Int?
    public let labels: [String]
    public let assignee: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    /// The `updatedAt` text, verbatim. Used as the revision.
    public let updatedAtRaw: String?
    public let closedAt: LoopDate?
    public let description: String?
    /// Every field not modelled above (for example `closeReason`, `extensions`, `seed`, `sections`), plus any
    /// modelled field whose value had an unexpected type.
    public let extra: [String: JSONValue]
    /// 1-based line in the store file.
    public let line: Int

    /// The slug from the first `project:<slug>` label.
    public var project: String? {
        labels.lazy.filter { $0.hasPrefix("project:") }.map { String($0.dropFirst("project:".count)) }
            .first { !$0.isEmpty }
    }

    /// True only for the owner's own finished statuses.
    public var isDoneInSource: Bool {
        switch store {
        case .issues: return status == "closed"
        case .plans: return status == "done"
        }
    }

    init?(_ object: [String: JSONValue], store: Store, line: Int, calendar: Calendar) {
        var fields = JSONFields(object)
        guard let id = fields.string("id"), !id.isEmpty else { return nil }
        self.store = store
        self.id = id
        self.line = line
        title = fields.string("title") ?? (store == .plans ? fields.string("name") : nil)
        status = fields.string("status")
        type = fields.string("type")
        priority = fields.int("priority")
        labels = fields.strings("labels") ?? []
        assignee = fields.string("assignee")
        description = fields.string("description")
        createdAt = fields.date("createdAt")
        updatedAt = JSONLines.date(object["updatedAt"]?.stringValue)
        updatedAtRaw = fields.string("updatedAt")
        closedAt = fields.loopDate("closedAt", calendar: calendar)
        extra = fields.remainder
    }

    public func openLoop(observedAt: Date, project inheritedProject: String? = nil) -> OpenLoop {
        OpenLoop(
            authority: .seeds, nativeID: id, title: title ?? id, kind: store == .plans ? "plan" : (type ?? "issue"),
            project: project ?? inheritedProject, nativeStatus: status ?? "", isDoneInSource: isDoneInSource,
            closed: closedAt, labels: labels, sourcePath: store.path, line: line, revision: updatedAtRaw,
            observedAt: observedAt)
    }
}

/// The readable content of a `.seeds/` store.
public struct SeedsSnapshot: Hashable, Sendable {
    public let issues: [SeedsRecord]
    public let plans: [SeedsRecord]
    /// `project:` from `.seeds/config.yaml`, when present.
    public let configProject: String?

    public init(issues: [SeedsRecord] = [], plans: [SeedsRecord] = [], configProject: String? = nil) {
        self.issues = issues
        self.plans = plans
        self.configProject = configProject
    }

    /// Issues and plans as open loops. A plan without its own `project:` label takes its seed issue's
    /// project (both are Seeds records, so no other owner is consulted).
    public func loops(observedAt: Date) -> [OpenLoop] {
        let issueProjects = Dictionary(issues.map { ($0.id, $0.project) }, uniquingKeysWith: { _, last in last })
        let planLoops = plans.map { plan in
            let seed = plan.extra["seed"]?.stringValue
            return plan.openLoop(observedAt: observedAt, project: seed.flatMap { issueProjects[$0] ?? nil })
        }
        return issues.map { $0.openLoop(observedAt: observedAt) } + planLoops
    }
}

/// Read-only parser for `.seeds/`. Never runs `sd` and never opens lock files.
public struct SeedsReader: OpenLoopSource {
    public let root: URL
    public let calendar: Calendar

    public init(root: URL, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
    }

    public var authority: LoopAuthority { .seeds }

    /// `uninitialized` without `.seeds/`; `partial` when a line could not be used (each issue names its line).
    /// Duplicate ids resolve as Seeds does: the last line wins, in the position of the first.
    public func readSnapshot(now: Date = Date()) -> SourceObservation<SeedsSnapshot> {
        let folder = root.appendingPathComponent(".seeds")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
            return SourceObservation(state: .uninitialized, value: SeedsSnapshot(), observedAt: now)
        }
        guard isDirectory.boolValue else {
            return SourceObservation(
                state: .unavailable(reason: ".seeds is not a folder"), value: SeedsSnapshot(), observedAt: now)
        }
        let vault = NoteVault(root: root)
        var issues: [SourceIssue] = []
        let issueRecords = read(.issues, vault: vault, required: true, issues: &issues)
        if let failure = issueRecords.failure {
            return SourceObservation(state: failure, value: SeedsSnapshot(), observedAt: now)
        }
        let plans = read(.plans, vault: vault, required: false, issues: &issues)
        let snapshot = SeedsSnapshot(
            issues: issueRecords.records, plans: plans.records, configProject: configProject(vault: vault))
        let count = snapshot.issues.count + snapshot.plans.count
        return SourceObservation(state: .readable(count: count, issues: issues), value: snapshot, observedAt: now)
    }

    public func readLoops(now: Date) -> SourceObservation<[OpenLoop]> {
        readSnapshot(now: now).map { $0.loops(observedAt: now) }
    }

    private func read(_ store: Store, vault: NoteVault, required: Bool, issues: inout [SourceIssue]) -> StoreRead {
        switch SourceFile.read(store.path, in: vault) {
        case .failed(let state):
            if case .unavailable = state, !required { return StoreRead() }
            if case .unavailable(let reason) = state {
                issues.append(SourceIssue(path: store.path, message: reason))
                return StoreRead()
            }
            return StoreRead(failure: state)
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                issues.append(SourceIssue(path: store.path, message: "not valid UTF-8"))
                return StoreRead()
            }
            return StoreRead(records: parse(text, store: store, issues: &issues))
        }
    }

    private func parse(_ text: String, store: Store, issues: inout [SourceIssue]) -> [SeedsRecord] {
        let parsed = JSONLines.parse(text, path: store.path)
        issues += parsed.issues
        var order: [String] = []
        var byID: [String: SeedsRecord] = [:]
        for row in parsed.rows {
            guard let record = SeedsRecord(row.object, store: store, line: row.line, calendar: calendar) else {
                issues.append(SourceIssue(path: store.path, line: row.line, message: "skipped record without an id"))
                continue
            }
            if record.status == nil {
                issues.append(SourceIssue(path: store.path, line: row.line, message: "record has no status"))
            }
            if byID[record.id] == nil { order.append(record.id) }
            byID[record.id] = record
        }
        return order.compactMap { byID[$0] }
    }

    private func configProject(vault: NoteVault) -> String? {
        guard case .data(let data) = SourceFile.read(".seeds/config.yaml", in: vault),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return Frontmatter(yaml: text).scalars["project"]
    }

    typealias Store = SeedsRecord.Store

    private struct StoreRead {
        var records: [SeedsRecord] = []
        var failure: SourceState?
    }
}
