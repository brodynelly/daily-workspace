import AppKit
import XCTest

@testable import DailyWorkspace

@MainActor
final class QuickPanelWorkspaceTabsTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
        super.tearDown()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qp-tabs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url.resolvingSymlinksInPath()
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line)
        async
    {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out", file: file, line: line)
    }

    // MARK: Parsing

    func testStatusParsingHandlesHeadRenamesAndUntracked() {
        let text =
            "## main...origin/main [ahead 2, behind 1]\0M  staged.swift\0 M edited.swift\0R  new.swift\0old.swift\0"
            + "?? notes/\0UU conflict.swift\0"
        let (head, files) = QuickPanelGitHub.parseStatus(text)
        XCTAssertEqual(head, QuickPanelGitHead(branch: "main", upstream: "origin/main", ahead: 2, behind: 1))
        XCTAssertEqual(files.map(\.path), ["staged.swift", "edited.swift", "new.swift", "notes/", "conflict.swift"])
        XCTAssertEqual(files[2].originalPath, "old.swift")
        XCTAssertTrue(files[0].hasStaged && !files[0].hasUnstaged)
        XCTAssertTrue(!files[1].hasStaged && files[1].hasUnstaged)
        XCTAssertTrue(files[3].isUntracked && files[3].hasUnstaged)
        XCTAssertTrue(files[4].isConflict && !files[4].hasStaged)
        XCTAssertEqual(QuickPanelGitHub.parseHead("No commits yet on trunk").branch, "trunk")
        XCTAssertEqual(QuickPanelGitHub.parseHead("feature").upstream, "")
        XCTAssertEqual(QuickPanelGitHub.parseHead("HEAD (no branch)").branch, "HEAD")
    }

    func testListParsingAndBranchNames() {
        let branches = QuickPanelGitHub.parseBranches(
            "*\u{1f}main\u{1f}origin/main\u{1f}2 hours ago\u{1f}Fix\n \u{1f}topic\u{1f}\u{1f}3 days ago\u{1f}Try\n")
        XCTAssertEqual(branches.map(\.name), ["main", "topic"])
        XCTAssertEqual(branches.map(\.isHead), [true, false])
        XCTAssertEqual(
            QuickPanelGitHub.parseCommits("abc1234\u{1f}Ann\u{1f}1 day ago\u{1f}Subject\n").first?.hash, "abc1234")
        XCTAssertEqual(
            QuickPanelGitHub.parseStashes("stash@{0}\u{1f}5 minutes ago\u{1f}WIP on main\n").first?.ref, "stash@{0}")
        XCTAssertTrue(QuickPanelGitHub.isValidBranchName("feature/tabs-2"))
        for bad in ["", "-x", "a..b", "a b", "x.lock", "a~1", "a:b", "end/", "@{u}x"] {
            XCTAssertFalse(QuickPanelGitHub.isValidBranchName(bad), bad)
        }
        XCTAssertEqual(
            QuickPanelGitClient.summary("hint: use --force\nerror: failed to push some refs\nmore"),
            "error: failed to push some refs")
    }

    // MARK: Git operations

    func testStageCommitBranchAndDiscardInARealRepository() async throws {
        let repo = try temporaryDirectory()
        let client = QuickPanelGitClient()
        for arguments in [
            ["init", "-q", "-b", "main"], ["config", "user.name", "Test"], ["config", "user.email", "t@example.com"],
            ["config", "commit.gpgsign", "false"], ["config", "core.hooksPath", "/dev/null"],
        ] {
            let result = await client.run(repo.path, arguments)
            XCTAssertTrue(result.ok, arguments.joined(separator: " "))
        }
        try write("one\n", to: repo.appendingPathComponent("a.txt"))
        let git = QuickPanelGitHub()
        git.open(path: repo.path, unavailable: nil)
        await waitUntil { git.files.count == 1 }
        XCTAssertTrue(git.files[0].isUntracked)

        git.toggleStage()
        await waitUntil { git.busy == nil && git.files.first?.hasStaged == true }
        git.beginCommit(amend: false)
        XCTAssertEqual(git.input, .commit)
        git.inputText = "First commit"
        git.submitInput()
        await waitUntil { git.busy == nil && git.files.isEmpty && git.commits.count == 1 }
        XCTAssertEqual(git.commits.first?.subject, "First commit")
        XCTAssertEqual(git.head.branch, "main")

        git.beginNewBranch()
        git.inputText = "topic"
        git.submitInput()
        await waitUntil { git.busy == nil && git.head.branch == "topic" }
        XCTAssertEqual(Set(git.branches.map(\.name)), ["main", "topic"])

        try write("two\n", to: repo.appendingPathComponent("a.txt"))
        await git.reload()
        XCTAssertEqual(git.files.first?.code, " M")
        git.requestDiscard()
        XCTAssertNotNil(git.confirmation, "Discard waits for y")
        git.confirm()
        await waitUntil { git.busy == nil && git.files.isEmpty }
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8), "one\n")
    }

    func testVaultDisablesGitAndOverviewKeysSwitchTabs() throws {
        let directory = try temporaryDirectory()
        let panel = QuickPanelController()
        var row = QuickPanelDataRow(
            id: "session:test", title: "test", detail: directory.path, group: "Sessions", action: .gotoSession("test"))
        row.path = directory.path
        panel.openWorkspaceDetail(for: row, path: directory.path)
        XCTAssertEqual(panel.workspaceTab, .overview)
        XCTAssertTrue(panel.rows.contains { $0.id == "detail:local:git" })
        XCTAssertTrue(panel.handleKey(keyCode: 0, characters: "]"))
        XCTAssertEqual(panel.workspaceTab, .git)
        XCTAssertEqual(panel.gitHub.path, directory.path)
        XCTAssertTrue(panel.handleKey(keyCode: 0, characters: "]"))
        XCTAssertEqual(panel.workspaceTab, .harness)
        XCTAssertTrue(panel.handleKey(keyCode: 0, characters: "]"))
        XCTAssertEqual(panel.workspaceTab, .overview)
        XCTAssertTrue(panel.handleKey(keyCode: 0, characters: "["))
        XCTAssertEqual(panel.workspaceTab, .harness)
        // Letters on the Git tab never fall through to the hidden overview rows.
        panel.selectWorkspaceTab(.git)
        XCTAssertTrue(panel.handleKey(keyCode: 0, characters: "o"))
        XCTAssertEqual(panel.workspacePath, directory.path)
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertNil(panel.workspacePath)
        XCTAssertEqual(panel.workspaceTab, .overview)
    }

    // MARK: Harness

    func testHarnessDiscoverySkipsSecretsCachesAndWorktrees() throws {
        let project = try temporaryDirectory()
        let home = try temporaryDirectory()
        try write("# Agents\n", to: project.appendingPathComponent("AGENTS.md"))
        try write("{}", to: project.appendingPathComponent(".claude/settings.json"))
        try write("x", to: project.appendingPathComponent(".claude/worktrees/w/AGENTS.md"))
        try write("x", to: project.appendingPathComponent(".pi/auth.json"))
        try write("skill", to: project.appendingPathComponent(".agents/skills/demo/SKILL.md"))
        try write("global", to: home.appendingPathComponent(".claude/CLAUDE.md"))
        try write("skill", to: home.appendingPathComponent(".claude/skills/s/SKILL.md"))
        try write("log", to: home.appendingPathComponent(".claude/projects/p/log.md"))
        try write("secret", to: home.appendingPathComponent(".codex/auth.json"))
        try write("model = 'x'", to: home.appendingPathComponent(".codex/config.toml"))

        let files = QuickPanelHarness.discover(project: project, home: home, projectReadOnly: false)
        let names = files.map { "\($0.group):\($0.name)" }
        XCTAssertEqual(
            names,
            [
                "Project:AGENTS.md", "Project:.claude/settings.json", "Project:.agents/skills/demo/SKILL.md",
                "~/.claude:CLAUDE.md", "~/.claude:skills/s/SKILL.md", "~/.codex:config.toml",
            ])
        XCTAssertTrue(files.allSatisfy(\.editable))
        let vault = QuickPanelHarness.discover(project: project, home: home, projectReadOnly: true)
        XCTAssertEqual(vault.filter { $0.group == "Project" }.map(\.editable), [false, false, false])
    }

    func testHarnessSaveRefusesOnDiskChangesAndKeepsPermissions() async throws {
        let project = try temporaryDirectory()
        let home = try temporaryDirectory()
        let file = project.appendingPathComponent(".claude/hooks/run.sh")
        try write("echo one\n", to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let harness = QuickPanelHarness()
        harness.home = home
        harness.open(path: project.path, readOnlyReason: nil)
        await waitUntil { !harness.loading && harness.content != nil }
        harness.beginEdit()
        XCTAssertTrue(harness.editing)
        harness.buffer = "echo two\n"
        try write("echo changed elsewhere\n", to: file)
        harness.save()
        XCTAssertTrue(harness.editing, "A conflicting save is refused")
        XCTAssertTrue(harness.noticeIsError)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "echo changed elsewhere\n")

        harness.escapeEdit()
        XCTAssertTrue(harness.editing, "First Escape with unsaved edits only warns")
        harness.escapeEdit()
        XCTAssertFalse(harness.editing)
        harness.rescan()
        await waitUntil { !harness.loading && harness.content == "echo changed elsewhere\n" }
        harness.beginEdit()
        harness.buffer = "echo three\n"
        harness.save()
        XCTAssertFalse(harness.editing)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "echo three\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o755)
    }

    func testHarnessAttachmentRedactsSecretsAndVaultFilesAreNotSent() async throws {
        XCTAssertEqual(
            QuickPanelHarness.redacted(#""apiKey": "abc123", "model": "opus""#), #""apiKey": [redacted]"#)
        XCTAssertEqual(QuickPanelHarness.redacted("GITHUB_TOKEN=ghp_x"), "GITHUB_TOKEN=[redacted]")
        XCTAssertEqual(
            QuickPanelHarness.redacted("use sk-ant-api03-abcdefghijklmnopqrstu here"), "use [redacted] here")
        XCTAssertEqual(QuickPanelHarness.redacted("model = 'opus'"), "model = 'opus'")

        let project = try temporaryDirectory()
        try write("ANTHROPIC_API_KEY=sk-secret-value\nrule\n", to: project.appendingPathComponent("AGENTS.md"))
        let harness = QuickPanelHarness()
        harness.home = try temporaryDirectory()
        harness.open(path: project.path, readOnlyReason: nil)
        await waitUntil { !harness.loading && harness.content != nil }
        let attachment = try XCTUnwrap(harness.attachment())
        XCTAssertFalse(attachment.contextText.contains("sk-secret-value"))
        XCTAssertTrue(attachment.contextText.contains("rule"))

        harness.open(path: project.path, readOnlyReason: "vault")
        await waitUntil { !harness.loading && harness.content != nil }
        XCTAssertNil(harness.attachment())
        harness.beginEdit()
        XCTAssertFalse(harness.editing)
    }
}
