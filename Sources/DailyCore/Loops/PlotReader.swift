import Foundation

/// A Plot attachment: a reference to a Seeds issue, a vault file, a PR…, with its role. Plot does not
/// dereference these, and neither does the app: a referenced Seeds issue keeps its own status.
public struct PlotReference: Hashable, Sendable {
    public let id: String?
    /// Verbatim: `seeds_issue`, `file`, `gh_pr`, `gh_issue`, `agent_run`, `mulch_record`…
    public let type: String
    public let ref: String
    /// Verbatim: `tracks`, `implements`, `informs`, `reference`…
    public let role: String?
    public let addedAt: Date?
    public let addedBy: String?

    public var isSeedsIssue: Bool { type == "seeds_issue" }
    public var isFile: Bool { type == "file" }
}

/// One line of a Plot event log.
public struct PlotEvent: Hashable, Sendable {
    /// Verbatim: `plot_created`, `attachment_added`, `note`, `decision_made`, `status_changed`…
    public let kind: String
    public let actor: String?
    public let at: Date?
    public let atRaw: String?
    /// The human-readable part of `data`: `text`, `summary`, `name`, or the referenced `path`/`ref`.
    public let text: String?
    /// The full `data` payload.
    public let data: [String: JSONValue]
    public let line: Int

    init(_ object: [String: JSONValue], line: Int) {
        var fields = JSONFields(object)
        kind = fields.string("type") ?? ""
        actor = fields.string("actor")
        at = JSONLines.date(object["at"]?.stringValue)
        atRaw = fields.string("at")
        let payload = object["data"]?.objectValue ?? [:]
        data = payload
        text = ["text", "summary", "name", "path", "ref"].lazy.compactMap { payload[$0]?.stringValue }.first
        self.line = line
    }
}

/// One Plot (`.plot/plot-xxxxxxxx.json`) with its event log (`plot-xxxxxxxx.events.jsonl`).
public struct PlotRecord: Hashable, Sendable {
    public let id: String
    /// The Plot's `name`.
    public let title: String
    /// Verbatim: `drafting`, `ready`, `active`, `done`, `archived`.
    public let status: String
    /// The human intent's `goal`; empty until a human enters it.
    public let goal: String?
    public let references: [PlotReference]
    public let events: [PlotEvent]
    public let createdAt: Date?
    public let updatedAt: Date?
    public let updatedAtRaw: String?
    /// Vault-relative path of the Plot JSON.
    public let path: String
    /// Fields not modelled above (`intent`, `schema_version`…).
    public let extra: [String: JSONValue]

    public var seedsIssueIDs: [String] { references.filter(\.isSeedsIssue).map(\.ref) }
    public var notePaths: [String] { references.filter(\.isFile).map(\.ref) }
    public var isDoneInSource: Bool { status == "done" || status == "archived" }

    public func openLoop(observedAt: Date) -> OpenLoop {
        OpenLoop(
            authority: .plot, nativeID: id, title: title.isEmpty ? id : title, kind: "plot", nativeStatus: status,
            isDoneInSource: isDoneInSource, sourcePath: path, revision: updatedAtRaw, observedAt: observedAt)
    }
}

/// Read-only parser for `.plot/`. Never runs `plot`, never opens its index database or lock files.
public struct PlotReader: OpenLoopSource {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var authority: LoopAuthority { .plot }

    public func readPlots(now: Date = Date()) -> SourceObservation<[PlotRecord]> {
        let folder = root.appendingPathComponent(".plot")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
            return SourceObservation(state: .uninitialized, value: [], observedAt: now)
        }
        let names: [String]
        do {
            guard isDirectory.boolValue else { throw CocoaError(.fileReadUnknown) }
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            let state = SourceFailure.state(for: error, missing: .uninitialized)
            return SourceObservation(state: state, value: [], observedAt: now)
        }
        let plotFiles = names.filter { $0.hasPrefix("plot-") && $0.hasSuffix(".json") }.sorted()
        let vault = NoteVault(root: root)
        var issues: [SourceIssue] = []
        let plots = plotFiles.compactMap { read($0, vault: vault, issues: &issues) }
        return SourceObservation(state: .readable(count: plots.count, issues: issues), value: plots, observedAt: now)
    }

    public func readLoops(now: Date) -> SourceObservation<[OpenLoop]> {
        readPlots(now: now).map { plots in plots.map { $0.openLoop(observedAt: now) } }
    }

    private func read(_ name: String, vault: NoteVault, issues: inout [SourceIssue]) -> PlotRecord? {
        let path = ".plot/\(name)"
        guard case .data(let data) = SourceFile.read(path, in: vault),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data), let object = value.objectValue
        else {
            issues.append(SourceIssue(path: path, message: "skipped plot: not a readable JSON object"))
            return nil
        }
        var fields = JSONFields(object)
        guard let id = fields.string("id") else {
            issues.append(SourceIssue(path: path, message: "skipped plot without an id"))
            return nil
        }
        let references = (object["attachments"]?.arrayValue ?? []).compactMap(Self.reference)
        fields.consume("attachments")
        let eventsPath = ".plot/\(id).events.jsonl"
        var events: [PlotEvent] = []
        if case .data(let eventData) = SourceFile.read(eventsPath, in: vault) {
            let parsed = JSONLines.parse(String(data: eventData, encoding: .utf8) ?? "", path: eventsPath)
            issues += parsed.issues
            events = parsed.rows.map { PlotEvent($0.object, line: $0.line) }
        }
        let goal = object["intent"]?["goal"]?.stringValue
        return PlotRecord(
            id: id, title: fields.string("name") ?? "", status: fields.string("status") ?? "", goal: goal,
            references: references, events: events, createdAt: fields.date("created_at"),
            updatedAt: JSONLines.date(object["updated_at"]?.stringValue), updatedAtRaw: fields.string("updated_at"),
            path: path, extra: fields.remainder)
    }

    private static func reference(_ value: JSONValue) -> PlotReference? {
        guard let object = value.objectValue, let ref = object["ref"]?.stringValue else { return nil }
        return PlotReference(
            id: object["id"]?.stringValue, type: object["type"]?.stringValue ?? "", ref: ref,
            role: object["role"]?.stringValue, addedAt: JSONLines.date(object["added_at"]?.stringValue),
            addedBy: object["added_by"]?.stringValue)
    }
}
