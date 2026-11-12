import Foundation

/// Discovers project hubs under `01-projects/`, applying the vault scope before reading any file.
public struct ProjectHubReader {
    public static let projectsFolder = "01-projects"

    public let root: URL
    public let scope: VaultScope
    /// Path components below `01-projects/` a hub may have (`3` = `01-projects/a/b/hub.md`).
    public let maxDepth: Int
    public let maxPurposeLength: Int

    public init(root: URL, scope: VaultScope = .standard, maxDepth: Int = 3, maxPurposeLength: Int = 600) {
        self.root = root
        self.scope = scope
        self.maxDepth = maxDepth
        self.maxPurposeLength = maxPurposeLength
    }

    /// `unavailable` without `01-projects/`; `partial` when folders or candidate files could not be read.
    public func read(now: Date = Date()) -> SourceObservation<[ProjectHub]> {
        let folder = root.appendingPathComponent(Self.projectsFolder)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            let reason = "\(Self.projectsFolder) was not found"
            return SourceObservation(state: .unavailable(reason: reason), value: [], observedAt: now)
        }
        let traversal = scope.traverse(root: root, subpath: Self.projectsFolder, maxDepth: maxDepth)
        if traversal.unreadablePaths == [Self.projectsFolder] {
            return SourceObservation(state: .unauthorized, value: [], observedAt: now)
        }
        var issues = traversal.unreadablePaths.map { SourceIssue(path: $0, message: "could not be listed") }
        var hubs: [ProjectHub] = []
        for file in traversal.files {
            guard let text = Self.text(of: file.url) else {
                issues.append(SourceIssue(path: file.path, message: "could not be read as UTF-8"))
                continue
            }
            guard let frontmatter = Frontmatter.split(markdown: text)?.frontmatter, Self.isHub(frontmatter) else {
                continue
            }
            hubs.append(hub(file: file, text: text, frontmatter: frontmatter, issues: &issues))
        }
        return SourceObservation(state: .readable(count: hubs.count, issues: issues), value: hubs, observedAt: now)
    }

    static func isHub(_ frontmatter: Frontmatter) -> Bool {
        frontmatter.scalars["type"]?.lowercased() == "project"
    }

    static func text(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func hub(file: VaultFile, text: String, frontmatter: Frontmatter, issues: inout [SourceIssue])
        -> ProjectHub
    {
        let folder = (file.path as NSString).deletingLastPathComponent
        let notesFolder = folder + "/notes"
        let notes = listNotes(in: notesFolder, issues: &issues)
        let siblings = scope.traverse(root: root, subpath: folder, maxDepth: 1).files.filter { $0.path != file.path }
        let state = newestState(among: siblings + notes.files)
        return ProjectHubParser.hub(
            text: text, path: file.path, modified: file.modified, maxPurposeLength: maxPurposeLength,
            notes: notes.notes, state: state)
    }

    private func listNotes(in folder: String, issues: inout [SourceIssue]) -> (notes: [ProjectNote], files: [VaultFile])
    {
        var isDirectory: ObjCBool = false
        let url = root.appendingPathComponent(folder)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return ([], []) }
        let traversal = scope.traverse(root: root, subpath: folder)
        issues += traversal.unreadablePaths.map { SourceIssue(path: $0, message: "could not be listed") }
        let notes = traversal.files.map { ProjectNote(path: $0.path, modified: $0.modified) }
        let sorted = notes.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        return (sorted, traversal.files)
    }

    private func newestState(among files: [VaultFile]) -> ProjectState? {
        let states = files.compactMap { file -> ProjectState? in
            guard let text = Self.text(of: file.url) else { return nil }
            let frontmatter = Frontmatter.split(markdown: text)?.frontmatter ?? Frontmatter()
            guard ProjectHubParser.isStateNote(path: file.path, frontmatter: frontmatter) else { return nil }
            return ProjectHubParser.state(text: text, path: file.path, modified: file.modified)
        }
        return states.max { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
    }
}

/// Pure parsing of hub and project-state notes.
public enum ProjectHubParser {
    private static let linkPattern = try? NSRegularExpression(
        pattern: #"\[([^\]]*)\]\((file://[^)\s]+)\)|(?<![(\w])(file:///[^\s)>\]`]+)"#)
    private static let localPathPattern = try? NSRegularExpression(
        pattern: #"(?i)local path\**\s*:\s*\**\s*`([^`]+)`"#)

    public static func hub(
        text: String, path: String, modified: Date? = nil, maxPurposeLength: Int = 600, notes: [ProjectNote] = [],
        state: ProjectState? = nil
    ) -> ProjectHub {
        let split = Frontmatter.split(markdown: text)
        let lines = SourceFile.lines(text)
        let body = lines[(split?.bodyStart ?? 0)...]
        let outline = MarkdownOutline(body)
        let slug = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let frontmatter = split?.frontmatter ?? Frontmatter()
        let purposeLines =
            MarkdownOutline.paragraphs(outline.preamble).isEmpty
            ? outline.sections.first?.lines ?? [] : outline.preamble
        let purpose = MarkdownOutline.paragraphs(purposeLines).joined(separator: "\n\n")
        return ProjectHub(
            slug: slug, title: outline.title ?? frontmatter.scalars["title"] ?? slug, path: path,
            tags: frontmatter.tags, frontmatter: frontmatter,
            purpose: purpose.isEmpty ? nil : MarkdownOutline.bounded(purpose, limit: maxPurposeLength),
            repositories: repositories(in: Array(lines)),
            decisions: MarkdownOutline.bullets(outline.section(matching: ["decisions and unknowns"])?.lines ?? []),
            notes: notes, modified: modified, state: state)
    }

    /// `file:///…` links and "Local path: `…`" lines, first occurrence of each path only.
    public static func repositories(in lines: [Substring]) -> [RepositoryReference] {
        var seen: Set<String> = []
        var references: [RepositoryReference] = []
        let code = MarkdownOutline.codeMask(lines)
        for (index, line) in lines.enumerated() where !code[index] {
            for reference in lineReferences(String(line), line: index + 1) where seen.insert(reference.path).inserted {
                references.append(reference)
            }
        }
        return references
    }

    private static func lineReferences(_ text: String, line: Int) -> [RepositoryReference] {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            match.range(at: index).location == NSNotFound ? nil : ns.substring(with: match.range(at: index))
        }
        let links = (linkPattern?.matches(in: text, range: range) ?? []).compactMap { match -> RepositoryReference? in
            guard let raw = group(match, 2) ?? group(match, 3), let path = URL(string: raw)?.path, !path.isEmpty
            else { return nil }
            return RepositoryReference(source: .fileLink, label: group(match, 1), path: normalized(path), line: line)
        }
        let local = (localPathPattern?.matches(in: text, range: range) ?? []).compactMap { match in
            group(match, 1).map {
                RepositoryReference(source: .localPath, label: nil, path: normalized($0), line: line)
            }
        }
        return links + local
    }

    /// Without a trailing slash, so a link and a "Local path" line to the same checkout match.
    private static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// A note shaped like `templates/project-state.md`: frontmatter `type: project-state` or the
    /// `project-state` tag (never `type: template`), or a `project-state`/`current-state` file name.
    public static func isStateNote(path: String, frontmatter: Frontmatter) -> Bool {
        if frontmatter.scalars["type"]?.lowercased() == "template" { return false }
        if frontmatter.scalars["type"]?.lowercased() == "project-state" { return true }
        if frontmatter.tags.contains(where: { $0.lowercased() == "project-state" }) { return true }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
        return ["project-state", "current-state"].contains { name == $0 || name.hasSuffix("-" + $0) }
    }

    public static func state(text: String, path: String, modified: Date? = nil) -> ProjectState {
        let lines = SourceFile.lines(text)
        let body = lines[(Frontmatter.split(markdown: text)?.bodyStart ?? 0)...]
        let outline = MarkdownOutline(body)
        let fields = inlineFields(Array(body))
        func value(_ aliases: [String]) -> String? {
            if let section = outline.section(matching: aliases) {
                let text = section.lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter {
                    !$0.isEmpty && $0 != "-"
                }
                if !text.isEmpty { return text.joined(separator: "\n") }
            }
            return aliases.lazy.compactMap { fields[$0] }.first
        }
        func list(_ aliases: [String]) -> [String] {
            MarkdownOutline.bullets(outline.section(matching: aliases)?.lines ?? [])
        }
        let restart = inlinePairs(outline.section(matching: ["exact restart"])?.lines ?? []).map {
            ProjectState.RestartField(key: $0.key, value: $0.value)
        }
        return ProjectState(
            path: path, modified: modified, definitionOfDone: value(["definition of done"]),
            currentState: value(["current state", "current reality"]),
            nextAction: value(["next exact action", "next executable action", "next action"]), restart: restart,
            hypothesis: value(["active hypothesis"]), blockers: list(["blockers"]), decisions: list(["decisions made"]))
    }

    /// `**Key:** value` lines (optionally bulleted), keyed by lower-cased key, first one wins.
    private static func inlineFields(_ lines: [Substring]) -> [String: String] {
        Dictionary(inlinePairs(lines).map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    private static let fieldPattern = try? NSRegularExpression(
        pattern: #"^\s*(?:[-*]\s+)?\*\*([^*]+?):?\*\*:?\s*(.*)$"#)

    private static func inlinePairs(_ lines: [Substring]) -> [(key: String, value: String)] {
        lines.compactMap { line in
            let text = String(line)
            let ns = text as NSString
            guard let match = fieldPattern?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
            else { return nil }
            let key = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let value = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : (key, value)
        }
    }
}
