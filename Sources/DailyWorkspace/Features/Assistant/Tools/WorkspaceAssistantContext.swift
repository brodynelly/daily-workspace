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
    private let luunaWorkStore: LuunaWorkStore
    private let calendarStore: CalendarStore
    private let ledger: RestartLedger
    private let scope: VaultScope
    private let calendar: Calendar
    /// The scoped note index for one vault, built once per refresh and shared by concurrent searches.
    private var notesIndex: (root: URL, task: Task<[IndexedNote], Never>)?

    init(
        vaultRoot: @escaping () -> URL?, openLoops: OpenLoopsStore, projects: ProjectsStore,
        luunaWork: LuunaWorkStore, calendarStore: CalendarStore, ledger: RestartLedger,
        scope: VaultScope = .standard, calendar: Calendar = .current
    ) {
        self.vaultRoot = vaultRoot
        self.openLoopsStore = openLoops
        self.projectsStore = projects
        self.luunaWorkStore = luunaWork
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
            throw ToolFailure("\(allowed.path) is not a Markdown note, so it was not read.")
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
            // Open Loops consent does not grant the Assistant access to Mail metadata.
            guard match != .mail else { throw ToolFailure("Mail is not available to the Assistant.") }
            if let reason = Self.unreadableReason(openLoopsStore.observations[match]) {
                throw ToolFailure("\(source) \(reason), so its items are unknown, not empty.")
            }
            authority = match
        }
        let loops = openLoopsStore.loops(authority: authority, project: project, includeDone: true)
            .filter { loop in
                loop.authority != .mail
                    && (status.map { loop.nativeStatus.caseInsensitiveCompare($0) == .orderedSame } ?? true)
            }
        return loops.prefix(Self.maxLoopRows).map(Self.row)
    }

    func unreadableLoopSources() async -> [String: String] {
        var reasons: [String: String] = [:]
        for authority in OpenLoopsStore.authorities {
            guard authority != .mail else { continue }
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
        guard let root = vaultRoot(), root.standardizedFileURL == projectsStore.vaultRoot?.standardizedFileURL else {
            throw ToolFailure("Project hubs for the selected vault are unavailable, not empty.")
        }
        guard let hubs = projectsStore.hubs else {
            throw ToolFailure("Project hubs have not been read yet. Try again in a moment.")
        }
        guard hubs.state.isReadable else { throw ToolFailure("Project hubs are unavailable, not empty.") }
        guard let hub = hubs.value.first(where: { $0.slug == slug }) else {
            let qualifier = hubs.state.issues.isEmpty ? "" : " in this partial inventory"
            throw ToolFailure(
                "There is no project hub with the slug \(slug)\(qualifier). Use list_projects to find a slug.")
        }
        guard let allowed = try? VaultReadPolicy.resolve(hub.path, root: root, scope: scope),
            allowed.path == hub.path, FileManager.default.fileExists(atPath: allowed.url.path)
        else {
            throw ToolFailure("The project hub is excluded or unavailable, so it was not read.")
        }
        let association = projectsStore.association(forHubPath: hub.path)
        let loops = openLoopsStore.loops(project: hub.projectKey, includeDone: true)
            .filter { $0.authority != .mail && $0.authority != .luuna }
        let nativeTickets: [ToolNativeTicket]
        let nativeTicketsUnavailable: String?
        if let binding = association?.luuna {
            do {
                nativeTickets = try tickets(for: binding)
                nativeTicketsUnavailable = nil
            } catch let failure as ToolFailure {
                nativeTickets = []
                nativeTicketsUnavailable = failure.message
            }
        } else {
            nativeTickets = []
            nativeTicketsUnavailable = nil
        }
        let ledger = ledger
        let latest: RestartRecord?
        do {
            latest = try await Task.detached(priority: .userInitiated) {
                try ledger.records(project: hub.slug).latest
            }.value
        } catch {
            throw ToolFailure("The restart ledger could not be read, so the latest restart record is unknown.")
        }
        // The association is the app's explicit binding; it supplies checkout paths, not ticket status.
        let checkouts = hub.repositories.map(\.path) + (association?.checkouts.map(\.path) ?? [])
        let notes = hub.notes.map(\.path) + (hub.state.map { [$0.path] } ?? [])
        return ToolProject(
            slug: hub.slug, title: hub.title, hubPath: hub.path, summary: hub.purpose, decisions: hub.decisions,
            checkouts: Self.unique(checkouts), openLoops: loops.prefix(Self.maxLoopRows).map(Self.row),
            nativeTickets: nativeTickets, nativeTicketsUnavailable: nativeTicketsUnavailable,
            relatedNotes: Self.unique(notes), latestRestart: latest)
    }

    /// Only current reads for this exact origin and project may describe its native work.
    private func tickets(for binding: LuunaProjectBinding) throws -> [ToolNativeTicket] {
        guard luunaWorkStore.observedProjectBinding == binding else {
            throw ToolFailure(
                "Luuna tickets for project \(binding.projectID) are unavailable: this project's runtime and "
                    + "project have not been selected and read. Items are unknown, not empty.")
        }
        let tickets = luunaWorkStore.tickets
        let board = luunaWorkStore.board
        guard tickets.state.isSuccess, tickets.state != .uninitialized,
            let records = tickets.value, let observedAt = tickets.lastSuccessAt
        else {
            throw ToolFailure(
                "Luuna tickets for project \(binding.projectID) are unavailable (\(tickets.state)). "
                    + "Items are unknown, not empty.")
        }
        var columns: [String: String] = [:]
        if board.state.isSuccess, board.state != .uninitialized, let placement = board.value {
            for card in placement.cards(forProjectID: binding.projectID) where card.kind.rawValue == "ticket" {
                if let id = card.ticketID { columns[id] = card.column.rawValue }
            }
        }
        return records.filter { $0.projectID == binding.projectID }.map { ticket in
            ToolNativeTicket(
                id: ticket.id, source: "luuna", title: ticket.title, status: ticket.status?.rawValue,
                boardColumn: columns[ticket.id], observedAt: observedAt)
        }
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

extension WorkspaceAssistantContext {
    func listProjects() async -> ToolProjectInventory {
        guard let root = vaultRoot(), root.standardizedFileURL == projectsStore.vaultRoot?.standardizedFileURL
        else {
            return ToolProjectInventory(
                state: "unavailable", projects: [], truncated: false,
                reason: "No selected vault has current project hubs.")
        }
        guard let hubs = projectsStore.hubs else {
            return ToolProjectInventory(
                state: "not_read", projects: [], truncated: false, reason: "Project hubs have not been read yet.")
        }
        let (state, reason) = Self.sourceDescription(for: hubs.state)
        // Failed refreshes retain the previous value as stale. Never expose it as a current inventory.
        guard hubs.state.isReadable else {
            return ToolProjectInventory(state: state, projects: [], truncated: false, reason: reason)
        }
        let candidates = hubs.value
        let scope = scope
        return await Task.detached(priority: .userInitiated) {
            var projects: [ToolProjectListing] = []
            var skipped = false
            for hub in candidates {
                guard let allowed = try? VaultReadPolicy.resolve(hub.path, root: root, scope: scope),
                    allowed.path == hub.path, FileManager.default.fileExists(atPath: allowed.url.path)
                else {
                    skipped = true
                    continue
                }
                if projects.count == AssistantTool.projectLimit {
                    return ToolProjectInventory(
                        state: skipped ? "partial" : state, projects: projects, truncated: true,
                        reason: skipped ? "Some registered hubs are now excluded or unavailable." : reason)
                }
                projects.append(ToolProjectListing(slug: hub.slug, title: hub.title, path: hub.path))
            }
            return ToolProjectInventory(
                state: skipped ? "partial" : state, projects: projects, truncated: false,
                reason: skipped ? "Some registered hubs are now excluded or unavailable." : reason)
        }.value
    }

    private static func sourceDescription(for state: SourceState) -> (state: String, reason: String?) {
        switch state {
        case .populated: ("populated", nil)
        case .empty: ("empty", nil)
        case .partial: ("partial", "Some project hubs could not be read; the inventory may be incomplete.")
        case .unsupported: ("unsupported", "Project hubs are not supported.")
        case .unauthorized: ("unauthorized", "Project hubs could not be accessed.")
        case .unavailable: ("unavailable", "Project hubs are unavailable.")
        case .uninitialized: ("uninitialized", "Project hubs have not been set up.")
        case .refused: ("refused", "Project hub access was refused.")
        }
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
