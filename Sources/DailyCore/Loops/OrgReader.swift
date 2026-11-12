import Foundation

/// One Org headline with its planning line and property drawer.
public struct OrgHeading: Hashable, Sendable {
    public let level: Int
    /// The to-do keyword, verbatim, or nil for a plain heading.
    public let keyword: String?
    public let isDone: Bool
    /// The priority cookie's value (`A` for `[#A]`).
    public let priority: String?
    public let title: String
    /// The heading's own tags (not inherited ones).
    public let tags: [String]
    public let scheduled: LoopDate?
    public let deadline: LoopDate?
    public let closed: LoopDate?
    /// The `:PROPERTIES:` drawer. Keys are upper-cased (Org keys are case-insensitive); values verbatim.
    public let properties: [String: String]
    /// Titles of the enclosing headings, outermost first.
    public let outline: [String]
    /// 1-based line of the headline.
    public let line: Int
    /// Hash of the heading's text up to the next headline.
    public let revision: String

    public var orgID: String? { properties["ID"].flatMap { $0.isEmpty ? nil : $0 } }
    public var created: LoopDate? { properties["CREATED"].flatMap(OrgTimestamp.parse) }
}

/// One parsed Org file.
public struct OrgDocument: Hashable, Sendable {
    /// Vault-relative path.
    public let path: String
    public let keywords: OrgTodoKeywords
    public let headings: [OrgHeading]

    /// Parses Org text. Pure: no file access.
    public init(text: String, path: String) {
        self.path = path
        let lines = SourceFile.lines(text)
        let keywords = OrgTodoKeywords.declared(in: lines) ?? .standard
        self.keywords = keywords
        var headings: [OrgHeading] = []
        var outline: [(level: Int, title: String)] = []
        let starts = lines.indices.compactMap { index in
            OrgHeadline(lines[index], keywords: keywords).map { (index, $0) }
        }
        for (position, start) in starts.enumerated() {
            let end = position + 1 < starts.count ? starts[position + 1].0 : lines.count
            let headline = start.1
            outline.removeAll { $0.level >= headline.level }
            let section = lines[start.0..<end]
            headings.append(
                Self.heading(headline, section: section, outline: outline.map(\.title), keywords: keywords))
            outline.append((headline.level, headline.title))
        }
        self.headings = headings
    }

    private static func heading(
        _ headline: OrgHeadline, section: ArraySlice<Substring>, outline: [String], keywords: OrgTodoKeywords
    ) -> OrgHeading {
        var body = section.dropFirst()
        var planning: [String: LoopDate] = [:]
        while let next = body.first, let entries = OrgTimestamp.planning(next) {
            planning.merge(entries) { first, _ in first }
            body = body.dropFirst()
        }
        let text = section.joined(separator: "\n")
        return OrgHeading(
            level: headline.level, keyword: headline.keyword,
            isDone: headline.keyword.map(keywords.isDone) ?? false, priority: headline.priority,
            title: headline.title, tags: headline.tags, scheduled: planning["SCHEDULED"],
            deadline: planning["DEADLINE"], closed: planning["CLOSED"], properties: Self.drawer(body),
            outline: outline, line: section.startIndex + 1, revision: SourceFailure.hash(Data(text.utf8)))
    }

    /// The property drawer, when it is the first thing after the headline and planning lines.
    private static func drawer(_ body: ArraySlice<Substring>) -> [String: String] {
        guard body.first?.trimmingCharacters(in: .whitespaces).uppercased() == ":PROPERTIES:" else { return [:] }
        var properties: [String: String] = [:]
        for line in body.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased() == ":END:" { break }
            guard trimmed.hasPrefix(":"), let close = trimmed.dropFirst().firstIndex(of: ":") else { continue }
            let key = trimmed[trimmed.index(after: trimmed.startIndex)..<close].uppercased()
            let value = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, properties[key] == nil { properties[key] = value }
        }
        return properties
    }

    /// Headings with a to-do keyword, as open loops. Done ones keep their done keyword as the status.
    /// The id is `org:<:ID:>` when the heading has one, else `org:<path>#<title>`, with `~2`, `~3`…
    /// appended to repeated titles in the same file.
    public func loops(observedAt: Date) -> [OpenLoop] {
        var seen: [String: Int] = [:]
        return headings.compactMap { heading in
            guard let keyword = heading.keyword else { return nil }
            let nativeID: String
            if let orgID = heading.orgID {
                nativeID = orgID
            } else {
                let base = "\(path)#\(heading.title)"
                seen[base, default: 0] += 1
                nativeID = seen[base] == 1 ? base : "\(base)~\(seen[base] ?? 1)"
            }
            return OpenLoop(
                authority: .org, nativeID: nativeID, title: heading.title, kind: "heading", nativeStatus: keyword,
                isDoneInSource: heading.isDone, scheduled: heading.scheduled, deadline: heading.deadline,
                closed: heading.closed, labels: heading.tags, sourcePath: path, line: heading.line,
                revision: heading.revision, observedAt: observedAt)
        }
    }
}

/// Read-only parser for the owner's Org files. Never writes `.org` files.
public struct OrgReader: OpenLoopSource {
    public static let defaultPaths = ["org/inbox.org", "org/projects.org"]

    public let root: URL
    public let paths: [String]
    public let scope: VaultScope

    public init(root: URL, paths: [String] = OrgReader.defaultPaths, scope: VaultScope = .standard) {
        self.root = root
        self.paths = paths
        self.scope = scope
    }

    public var authority: LoopAuthority { .org }

    /// Every configured file that could be read. Files that could not are issues (`partial`); when none
    /// could, the state says why (`unavailable` for missing files, `unauthorized`, `refused`).
    public func readDocuments(now: Date = Date()) -> SourceObservation<[OrgDocument]> {
        let vault = NoteVault(root: root)
        var documents: [OrgDocument] = []
        var failures: [(path: String, state: SourceState)] = []
        for path in paths {
            if (try? vault.resolve(relativePath: path)) == nil {
                failures.append((path, .refused(reason: "\(path) resolves outside the vault")))
                continue
            }
            if let exclusion = scope.exclusion(forPath: path, isDirectory: false) {
                failures.append((path, .refused(reason: "\(path) is excluded (\(exclusion.rawValue))")))
                continue
            }
            switch SourceFile.read(path, in: vault) {
            case .failed(let state):
                failures.append((path, state))
            case .data(let data):
                guard let text = String(data: data, encoding: .utf8) else {
                    failures.append((path, .unavailable(reason: "\(path) is not valid UTF-8")))
                    continue
                }
                documents.append(OrgDocument(text: text, path: path))
            }
        }
        if documents.isEmpty, let first = failures.first {
            return SourceObservation(state: first.state, value: [], observedAt: now)
        }
        let issues = failures.map { SourceIssue(path: $0.path, message: Self.describe($0.state)) }
        let count = documents.reduce(0) { $0 + $1.headings.filter { $0.keyword != nil }.count }
        return SourceObservation(state: .readable(count: count, issues: issues), value: documents, observedAt: now)
    }

    public func readLoops(now: Date) -> SourceObservation<[OpenLoop]> {
        readDocuments(now: now).map { documents in documents.flatMap { $0.loops(observedAt: now) } }
    }

    private static func describe(_ state: SourceState) -> String {
        switch state {
        case .unavailable(let reason), .refused(let reason): return reason
        case .unauthorized: return "permission denied"
        default: return "could not be read"
        }
    }
}
