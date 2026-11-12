import XCTest

@testable import DailyCore

final class VaultScopeTests: XCTestCase {
    func testPathRules() {
        let scope = VaultScope.standard
        let cases: [(String, VaultExclusion?)] = [
            ("notes/a.md", nil),
            (".obsidian/x.md", .hidden),
            ("a/.notes/b.md", .hidden),
            ("_ingest/a.md", .underscored),
            ("a/_control.md", .underscored),
            ("04-archive/old.md", .archive),
            ("04-archive", .archive),
            ("templates/project-state.md", .templates),
            ("00-inbox/automation/report.md", .automation),
            ("00-inbox/.ingest/kb-intake/t.md", .rawIngest),
            ("00-inbox/remarkable/scan.md", .rawIngest),
            ("01-projects/nas/operations/nas-alerts-board.md", .generatedBoard),
            ("01-projects/work/kotc/kotc-kanban.md", .generatedBoard),
            ("01-projects/work/homebase/homebase-board-background.md", nil),
            ("00-inbox/automation-notes.md", nil),
            ("templates.md", nil),
        ]
        for (path, expected) in cases {
            XCTAssertEqual(scope.exclusion(forPath: path, isDirectory: false), expected, path)
        }
        XCTAssertNil(scope.exclusion(forPath: "01-projects/x-board.md", isDirectory: true))
    }

    func testTraversalSkipsEachClassBeforeReading() throws {
        let vault = try FixtureVault()
        let outside = try FixtureVault()
        try outside.write("secret.md", "outside")
        let files = [
            "keep.md", "01-projects/p/keep.md", ".hidden/a.md", "_control/a.md", "04-archive/a.md", "templates/a.md",
            "00-inbox/automation/a.md", "00-inbox/.ingest/a.md", "00-inbox/remarkable/a.md",
            "01-projects/p/p-board.md", "01-projects/p/p-kanban.md", "repo/.git/HEAD", "repo/a.md", "keep.txt",
        ]
        for path in files { try vault.write(path, "- [ ] item\n") }
        try vault.link("linked.md", to: outside.root.appendingPathComponent("secret.md"))
        try vault.link("linked-folder", to: outside.root)

        let traversal = VaultScope.standard.traverse(root: vault.root)
        XCTAssertEqual(traversal.files.map(\.path), ["01-projects/p/keep.md", "keep.md"])
        XCTAssertEqual(traversal.skipped(.hidden), 1)
        XCTAssertEqual(traversal.skipped(.underscored), 1)
        XCTAssertEqual(traversal.skipped(.archive), 1)
        XCTAssertEqual(traversal.skipped(.templates), 1)
        XCTAssertEqual(traversal.skipped(.automation), 1)
        XCTAssertEqual(traversal.skipped(.rawIngest), 2)
        XCTAssertEqual(traversal.skipped(.generatedBoard), 2)
        XCTAssertEqual(traversal.skipped(.nestedRepository), 1)
        XCTAssertEqual(traversal.skipped(.symlink), 2)
        XCTAssertTrue(traversal.isComplete)
    }

    func testUnreadableFolderIsCountedNotSilent() throws {
        let vault = try FixtureVault()
        try vault.write("open/a.md", "a")
        try vault.write("locked/b.md", "b")
        let locked = vault.root.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let traversal = VaultScope.standard.traverse(root: vault.root)
        XCTAssertEqual(traversal.files.map(\.path), ["open/a.md"])
        XCTAssertEqual(traversal.unreadablePaths, ["locked"])
        XCTAssertEqual(traversal.skippedUnreadable, 1)
        XCTAssertFalse(traversal.isComplete)
    }

    func testScopedIndexIsOptInAndReportsUnreadableNotes() throws {
        let vault = try FixtureVault()
        try vault.write("a.md", "alpha")
        try vault.write("04-archive/b.md", "archived")
        try vault.write("p/x-board.md", "board")
        try Data([0xff, 0xfe]).write(to: vault.root.appendingPathComponent("bad.md"))

        let unscoped = try VaultIndex.scan(root: vault.root)
        XCTAssertEqual(unscoped.map(\.path), ["04-archive/b.md", "a.md", "p/x-board.md"], "scan(root:) is unchanged")

        let scoped = VaultIndex.scan(root: vault.root, scope: .standard)
        XCTAssertEqual(scoped.notes.map(\.path), ["a.md"])
        XCTAssertEqual(scoped.unreadableNotes, ["bad.md"])
        XCTAssertEqual(scoped.skippedUnreadable, 1)
        XCTAssertFalse(scoped.isComplete)
        XCTAssertEqual(scoped.traversal.skipped(.archive), 1)
        XCTAssertEqual(scoped.traversal.skipped(.generatedBoard), 1)
    }
}
