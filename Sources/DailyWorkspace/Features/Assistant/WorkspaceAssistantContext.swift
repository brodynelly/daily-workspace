import DailyCore
import Foundation

/// The Assistant's tools over the app's real sources. Everything here is read-only: it reads the vault through
/// the exclusion policy, the stores' latest observations, Calendar through its store and the restart ledger.
/// Statuses, ids and paths are copied from the owners verbatim. File reads run off the main actor.
@MainActor
final class WorkspaceAssistantContext: AssistantContext {
    /// Most open-loop rows one call returns (not-done first).
    static let maxLoopRows = 200

    private let vaultRoot: () -> URL?
    private let openLoopsStore: OpenLoopsStore
    private let projectsStore: ProjectsStore
    private let calendarStore: CalendarStore
    private let ledger: RestartLedger
    private let scope: VaultScope
    private let calendar: Calendar
    /// The scoped note index for one vault, built once per refresh and shared by concurrent searches.
    private var notesIndex: (root: URL, task: Task<[IndexedNote], Never>)?

    init(
        vaultRoot: @escaping () -> URL?, openLoops: OpenLoopsStore, projects: ProjectsStore,
        calendarStore: CalendarStore, ledger: RestartLedger, scope: VaultScope = .standard,
        calendar: Calendar = .current
    ) {
        self.vaultRoot = vaultRoot
        self.openLoopsStore = openLoops
        self.projectsStore = projects
        self.calendarStore = calendarStore
        self.ledger = ledger
        self.scope = scope
        self.calendar = calendar
    }

    /// Drop the note index so the next search scans again (on refresh and vault change).
    func invalidateNotes() {
        notesIndex = nil
    }

    // MARK: Notes

    func searchNotes(query: String, limit: Int) async throws -> [ToolNoteHit] {
        let root = try requireVault()
        let notes = await index(root: root)
        return await Task.detached(priority: .userInitiated) {
            NoteSearch.hits(for: query, in: notes, limit: limit)
        }.value
    }

    func readNote(path: String, maxBytes: Int) async throws -> ToolNote {
        let root = try requireVault()
        let scope = scope
        return try await Task.detached(priority: .userInitiated) {
            let allowed = try VaultReadPolicy.resolve(path, root: root, scope: scope)
            return try Self.read(allowed, maxBytes: maxBytes)
        }.value
    }

    private func index(root: URL) async -> [IndexedNote] {
        if let notesIndex, notesIndex.root == root { return await notesIndex.task.value }
        let scope = scope
        let task = Task.detached(priority: .userInitiated) { VaultIndex.scan(root: root, scope: scope).notes }
        notesIndex = (root, task)
        return await task.value
    }

    /// At most `maxBytes` of the note, without reading the rest of the file.
    nonisolated static func read(_ allowed: VaultReadPolicy.Allowed, maxBytes: Int) throws -> ToolNote {
        guard VaultReadPolicy.noteExtensions.contains(allowed.url.pathExtension.lowercased()) else {
            throw ToolFailure("\(allowed.path) is not a Markdown or Org note, so it was not read.")
        }
        guard FileManager.default.fileExists(atPath: allowed.url.path) else {
            throw ToolFailure("There is no note at \(allowed.path).")
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: allowed.url)
        } catch {
            throw ToolFailure("\(allowed.path) could not be opened.")
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxBytes + 1)) ?? Data()
        let truncated = data.count > maxBytes
        var bytes = Data(data.prefix(maxBytes))
        var text = String(data: bytes, encoding: .utf8)
        // The cut may split one UTF-8 character (at most 3 trailing bytes).
        var dropped = 0
        while text == nil, truncated, dropped < 3, !bytes.isEmpty {
            bytes.removeLast()
            dropped += 1
            text = String(data: bytes, encoding: .utf8)
        }
        guard let text else { throw ToolFailure("\(allowed.path) is not UTF-8 text, so it was not read.") }
        return ToolNote(path: allowed.path, text: text, truncated: truncated)
    }

    // MARK: Open loops

    func openLoops(source: String?, project: String?, status: String?) async throws -> [ToolLoopRow] {
        var authority: LoopAuthority?
        if let source {
            guard let match = LoopAuthority(rawValue: source) else {
                throw ToolFailure("There is no source \(source).")
            }
            if let reason = Self.unreadableReason(openLoopsStore.observations[match]) {
                throw ToolFailure("\(source) \(reason), so its items are unknown, not empty.")
            }
            authority = match
        }
        let loops = openLoopsStore.loops(authority: authority, project: project, includeDone: true)
            .filter { loop in status.map { loop.nativeStatus.caseInsensitiveCompare($0) == .orderedSame } ?? true }
        return loops.prefix(Self.maxLoopRows).map(Self.row)
    }

    func unreadableLoopSources() async -> [String: String] {
        var reasons: [String: String] = [:]
        for authority in OpenLoopsStore.authorities {
            if let reason = Self.unreadableReason(openLoopsStore.observations[authority]) {
                reasons[authority.rawValue] = reason
            }
        }
        return reasons
    }

    /// Why a source's items are unknown, or nil when its latest read is current.
    static func unreadableReason<Value>(_ observation: SourceObservation<Value>?) -> String? {
        guard let observation else { return "has not been read yet" }
        switch observation.state {
        case .partial, .empty, .populated: return nil
        case .unsupported: return "is not supported on this Mac"
        case .unauthorized: return "is not allowed (no permission)"
        case .unavailable(let reason): return "is unavailable (\(reason))"
        case .uninitialized: return "is not set up in this vault"
        case .refused(let reason): return "was refused (\(reason))"
        }
    }

    /// The owner's row, verbatim: the authority-qualified id, the native status and the source path.
    static func row(_ loop: OpenLoop) -> ToolLoopRow {
        ToolLoopRow(
            id: loop.id, source: loop.authority.rawValue, title: loop.title, status: loop.nativeStatus,
            project: loop.project, path: loop.sourcePath, scheduled: loop.scheduled?.raw,
            deadline: loop.deadline?.raw, observedAt: loop.observedAt)
    }

    // MARK: Projects

    func project(slug: String) async throws -> ToolProject {
        guard let hubs = projectsStore.hubs else {
            throw ToolFailure("Project hubs have not been read yet. Try again in a moment.")
        }
        guard let hub = hubs.value.first(where: { $0.slug == slug }) else {
            if let reason = Self.unreadableReason(hubs) { throw ToolFailure("Project hubs \(reason).") }
            let known = hubs.value.map(\.slug).sorted().joined(separator: ", ")
            throw ToolFailure("There is no project hub with the slug \(slug). Known slugs: \(known).")
        }
        let detail = ProjectsStore.detail(
            for: hub, seeds: projectsStore.seeds?.value ?? SeedsSnapshot(), plots: projectsStore.plots?.value ?? [])
        let seedsAt = projectsStore.seeds?.observedAt ?? Date()
        let plotsAt = projectsStore.plots?.observedAt ?? Date()
        let loops =
            detail.issues.map { $0.openLoop(observedAt: seedsAt) }
            + detail.plans.map { $0.openLoop(observedAt: seedsAt, project: hub.projectKey) }
            + detail.plots.map { $0.openLoop(observedAt: plotsAt) }
        let ledger = ledger
        let latest: RestartRecord?
        do {
            latest = try await Task.detached(priority: .userInitiated) {
                try ledger.records(project: hub.slug).latest
            }.value
        } catch {
            throw ToolFailure("The restart ledger could not be read, so the latest restart record is unknown.")
        }
        let association = projectsStore.association(forHubPath: hub.path)
        let checkouts = hub.repositories.map(\.path) + (association?.checkouts.map(\.path) ?? [])
        let notes = hub.notes.map(\.path) + (hub.state.map { [$0.path] } ?? [])
        return ToolProject(
            slug: hub.slug, title: hub.title, hubPath: hub.path, summary: hub.purpose, decisions: hub.decisions,
            checkouts: Self.unique(checkouts), openLoops: loops.prefix(Self.maxLoopRows).map(Self.row),
            relatedNotes: Self.unique(notes), latestRestart: latest)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: Calendar

    func agenda(day: LocalDay) async throws -> [ToolEvent] {
        switch calendarStore.authorization {
        case .authorized:
            break
        case .notRequested, .denied, .restricted:
            throw ToolFailure("Calendar access is not allowed, so the agenda is unknown, not empty.")
        case .unavailable:
            throw ToolFailure("Calendar is unavailable right now, so the agenda is unknown, not empty.")
        }
        guard let start = day.date(in: calendar), let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw ToolFailure("\(day) could not be placed on the calendar.")
        }
        return calendarStore.events(from: start, to: end).map {
            ToolEvent(
                id: $0.id, title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay,
                calendar: $0.calendarTitle, location: $0.location)
        }
    }

    private func requireVault() throws -> URL {
        guard let root = vaultRoot() else { throw ToolFailure("No vault is chosen, so notes can't be read.") }
        return root
    }
}

/// Lexical note search for the Assistant: every word must appear in the path or the text. Notes whose title
/// matches come first; each hit carries a short snippet around the first match.
enum NoteSearch {
    static let snippetLength = 200

    static func hits(for query: String, in notes: [IndexedNote], limit: Int) -> [ToolNoteHit] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = VaultIndex.search(query, in: notes)
        let ranked = matches.enumerated().sorted { lhs, rhs in
            let left = titleScore(lhs.element, terms)
            let right = titleScore(rhs.element, terms)
            return left != right ? left > right : lhs.offset < rhs.offset
        }
        return ranked.prefix(max(limit, 0)).map { _, note in
            ToolNoteHit(path: note.path, title: note.title, snippet: snippet(note.text, terms: terms))
        }
    }

    private static func titleScore(_ note: IndexedNote, _ terms: [String]) -> Int {
        terms.filter { note.title.localizedCaseInsensitiveContains($0) }.count
    }

    /// About `snippetLength` characters around the first matching word, on one line.
    static func snippet(_ text: String, terms: [String]) -> String {
        let hit = terms.lazy.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }
            .first
        let start =
            hit.map { text.index($0.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex }
            ?? text.startIndex
        let end = text.index(start, offsetBy: snippetLength, limitedBy: text.endIndex) ?? text.endIndex
        let body = text[start..<end].split(whereSeparator: \.isNewline).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return (start > text.startIndex ? "…" : "") + body + (end < text.endIndex ? "…" : "")
    }
}
