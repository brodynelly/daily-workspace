import AppKit
import Foundation

/// The workspace page's Git tab: a lazygit-style hub over one repository. Every command is a fixed `git` argv run
/// in that directory; destructive ones (discard, drop, delete, amend, merge) wait for a `y` confirmation, and a
/// discarded untracked file goes to the Trash rather than being deleted.
@MainActor
final class QuickPanelGitHub: ObservableObject {
    @Published private(set) var path: String?
    /// Why the hub is off for this directory (the vault, or not a repository); nil when it works.
    @Published private(set) var unavailable: String?
    @Published var section: QuickPanelGitSection = .files { didSet { loadPreview() } }
    @Published private(set) var head = QuickPanelGitHead()
    @Published private(set) var files: [QuickPanelGitFile] = []
    @Published private(set) var branches: [QuickPanelGitBranch] = []
    @Published private(set) var commits: [QuickPanelGitCommit] = []
    @Published private(set) var stashes: [QuickPanelGitStash] = []
    @Published private(set) var selection: [QuickPanelGitSection: Int] = [:]
    @Published private(set) var preview: [QuickPanelGitPreviewLine] = []
    @Published var previewScroll = 0
    @Published var busy: String?
    @Published var notice: String?
    @Published var noticeIsError = false
    @Published var input: QuickPanelGitInput?
    @Published var inputText = ""
    @Published var confirmation: QuickPanelGitConfirmation?
    @Published private(set) var loading = false

    private var generation = 0
    private var previewGeneration = 0
    var git = QuickPanelGitClient()

    static let previewLineLimit = 2_000

    func open(path: String, unavailable reason: String?) {
        generation += 1
        self.path = path
        unavailable = reason
        files = []
        branches = []
        commits = []
        stashes = []
        selection = [:]
        preview = []
        head = .init()
        notice = nil
        input = nil
        confirmation = nil
        busy = nil
        section = .files
        guard reason == nil else { return }
        Task { await reload() }
    }

    func close() {
        generation += 1
        path = nil
        unavailable = nil
        input = nil
        confirmation = nil
    }

    var count: Int { count(of: section) }

    func count(of section: QuickPanelGitSection) -> Int {
        switch section {
        case .files: files.count
        case .branches: branches.count
        case .commits: commits.count
        case .stash: stashes.count
        }
    }

    func selectedIndex(_ section: QuickPanelGitSection) -> Int {
        min(selection[section] ?? 0, max(0, count(of: section) - 1))
    }

    var selectedFile: QuickPanelGitFile? {
        files.indices.contains(selectedIndex(.files)) ? files[selectedIndex(.files)] : nil
    }
    var selectedBranch: QuickPanelGitBranch? {
        branches.indices.contains(selectedIndex(.branches)) ? branches[selectedIndex(.branches)] : nil
    }
    var selectedCommit: QuickPanelGitCommit? {
        commits.indices.contains(selectedIndex(.commits)) ? commits[selectedIndex(.commits)] : nil
    }
    var selectedStash: QuickPanelGitStash? {
        stashes.indices.contains(selectedIndex(.stash)) ? stashes[selectedIndex(.stash)] : nil
    }

    func move(by step: Int) {
        select(selectedIndex(section) + step)
    }

    func select(_ index: Int, in target: QuickPanelGitSection? = nil) {
        let target = target ?? section
        let next = min(max(0, index), max(0, count(of: target) - 1))
        if target != section { section = target }
        guard selection[target] != next else { return }
        selection[target] = next
        loadPreview()
    }

    func cycleSection(reverse: Bool) {
        let all = QuickPanelGitSection.allCases
        let position = all.firstIndex(of: section) ?? 0
        section = all[(position + (reverse ? all.count - 1 : 1)) % all.count]
    }

    func scrollPreview(by lines: Int) {
        previewScroll = min(max(0, previewScroll + lines), max(0, preview.count - 1))
    }

    // MARK: Loading

    func reload() async {
        guard let path, unavailable == nil else { return }
        generation += 1
        let current = generation
        loading = true
        defer { if current == generation { loading = false } }
        let git = self.git
        async let status = git.run(path, ["status", "--porcelain=v1", "-z", "--branch"])
        async let branchList = git.run(
            path,
            [
                "for-each-ref", "--sort=-committerdate",
                "--format=%(HEAD)%1f%(refname:short)%1f%(upstream:short)%1f%(committerdate:relative)%1f%(subject)",
                "refs/heads",
            ])
        async let log = git.run(path, ["log", "-n", "300", "--format=%h%x1f%an%x1f%ar%x1f%s"])
        async let stashList = git.run(path, ["stash", "list", "--format=%gd%x1f%cr%x1f%gs"])
        let results = await (status, branchList, log, stashList)
        guard current == generation else { return }
        guard results.0.ok else {
            unavailable = "Not a Git repository (or Git could not read it)"
            return
        }
        (head, files) = Self.parseStatus(results.0.output)
        branches = results.1.ok ? Self.parseBranches(results.1.output) : []
        commits = results.2.ok ? Self.parseCommits(results.2.output) : []
        stashes = results.3.ok ? Self.parseStashes(results.3.output) : []
        loadPreview()
    }

    func loadPreview() {
        previewGeneration += 1
        let current = previewGeneration
        previewScroll = 0
        guard let path, unavailable == nil else {
            preview = []
            return
        }
        let git = self.git
        let request: () async -> String
        switch section {
        case .files:
            guard let file = selectedFile else { return setPreview("No changes. Working tree clean.") }
            request = { await Self.fileDiff(file, in: path, git: git) }
        case .branches:
            guard let branch = selectedBranch else { return setPreview("No branches") }
            request = {
                let result = await git.run(
                    path, ["log", "-n", "60", "--graph", "--format=%h %ar  %s  (%an)", branch.name, "--"])
                return result.ok ? result.output : result.message
            }
        case .commits:
            guard let commit = selectedCommit else { return setPreview("No commits yet") }
            request = {
                let result = await git.run(path, ["show", "--stat", "--patch", "--no-color", commit.hash, "--"])
                return result.ok ? result.output : result.message
            }
        case .stash:
            guard let stash = selectedStash else { return setPreview("No stashes") }
            request = {
                let result = await git.run(path, ["stash", "show", "--stat", "--patch", "--no-color", stash.ref])
                return result.ok ? result.output : result.message
            }
        }
        Task {
            let text = await request()
            guard current == self.previewGeneration else { return }
            self.setPreview(text)
        }
    }

    private func setPreview(_ text: String) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        if lines.count > Self.previewLineLimit {
            let hidden = lines.count - Self.previewLineLimit
            lines = Array(lines.prefix(Self.previewLineLimit)) + ["… \(hidden) more lines"]
        }
        preview = lines.enumerated().map { .init(id: $0.offset, text: $0.element) }
    }

    nonisolated static func fileDiff(_ file: QuickPanelGitFile, in root: String, git: QuickPanelGitClient) async
        -> String
    {
        if file.isUntracked {
            let url = URL(fileURLWithPath: root).appendingPathComponent(file.path)
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
                return "Untracked directory \(file.path)\n\nStage it with space to add everything inside."
            }
            guard let handle = try? FileHandle(forReadingFrom: url) else { return "Could not read \(file.path)" }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
            if data.contains(0) { return "Binary file \(file.path)" }
            let text = String(bytes: data, encoding: .utf8) ?? "(not UTF-8 text)"
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { "+\($0)" }
            return "New file \(file.path)\n\n" + lines.joined(separator: "\n")
        }
        var text = ""
        if file.hasStaged {
            let staged = await git.run(root, ["diff", "--cached", "--no-color", "--", file.path])
            text += staged.output
        }
        if file.hasUnstaged || file.isConflict {
            let unstaged = await git.run(root, ["diff", "--no-color", "--", file.path])
            if !text.isEmpty && !unstaged.output.isEmpty { text += "\n── unstaged ──\n" }
            text += unstaged.output
        }
        return text.isEmpty ? "No textual diff for \(file.path) (\(file.code))" : text
    }
}
