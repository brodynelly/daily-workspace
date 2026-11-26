import AppKit
import XCTest

@testable import DailyWorkspace

@MainActor
final class QuickPanelWorkspacePageTests: XCTestCase {
    func testStatusParsingCountsBranchAndChanges() {
        var report = QuickPanelWorkspaceReport()
        QuickPanelWorkspaceReader.applyStatus(
            """
            # branch.oid abc
            # branch.head main
            # branch.upstream origin/main
            # branch.ab +2 -1
            1 M. N... 100644 100644 100644 a b staged.swift
            1 .M N... 100644 100644 100644 a b edited.swift
            1 MM N... 100644 100644 100644 a b both.swift
            u UU N... 100644 100644 100644 100644 a b c conflict.swift
            ? new.swift
            """, to: &report)
        XCTAssertEqual(report.branch, "main")
        XCTAssertEqual(report.upstream, "origin/main")
        XCTAssertEqual([report.ahead, report.behind], [2, 1])
        XCTAssertEqual([report.staged, report.modified, report.untracked, report.conflicts], [2, 2, 1, 1])
    }

    func testLogCountsDaysAndAgentCoAuthors() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let today = Int(now.timeIntervalSince1970) - 60
        let tenDaysAgo = today - 10 * 86_400
        let log =
            "\(today)\u{1f}Fix\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n\u{1e}"
            + "\(today)\u{1f}Manual change\n\u{1e}"
            + "\(tenDaysAgo)\u{1f}Older\n\nCo-authored-by: Codex <codex@openai.com>\n\u{1e}"
        var report = QuickPanelWorkspaceReport()
        QuickPanelWorkspaceReader.applyLog(log, now: now, to: &report)
        XCTAssertEqual(report.commits30Days, 3)
        XCTAssertEqual(report.commits7Days, 2)
        XCTAssertEqual(report.agentCommits30Days, 2)
        XCTAssertEqual(report.dailyCommits.last, 2)
        XCTAssertEqual(report.dailyCommits[3], 1)
    }

    func testShortstatAndHotFiles() {
        let (added, removed) = QuickPanelWorkspaceReader.parseShortstat(
            " 3 files changed, 40 insertions(+), 2 deletions(-)\n 1 file changed, 1 insertion(+)\n")
        XCTAssertEqual([added, removed], [41, 2])
        XCTAssertEqual(
            QuickPanelWorkspaceReader.topFiles("a/x.swift\nb/y.swift\na/x.swift\n", limit: 1), ["x.swift ×2"])
    }

    func testReturnOnHomeRowOpensPageAndKeepsKittyActionOnCommandReturn() throws {
        let panel = QuickPanelController()
        let path = FileManager.default.temporaryDirectory.standardizedFileURL.path
        var row = QuickPanelDataRow(
            id: "session:test", title: "test", detail: path, group: "Sessions", action: .gotoSession("test"))
        row.path = path
        XCTAssertEqual(panel.workspaceDetailPath(for: row), (path as NSString).standardizingPath)
        panel.openWorkspaceDetail(for: row, path: path)
        XCTAssertEqual(panel.workspacePath, path)
        let first = try XCTUnwrap(panel.rows.first)
        XCTAssertEqual(first.action, .gotoSession("test"))
        XCTAssertTrue(panel.rows.allSatisfy { $0.alternate == .gotoSession("test") })
        XCTAssertTrue(panel.handleKey(keyCode: 53))
        XCTAssertNil(panel.workspacePath)

        row.path = "/definitely/not/here"
        XCTAssertNil(panel.workspaceDetailPath(for: row))
    }

    func testProcessParsingAndMonitorRows() {
        let processes = QuickPanelMonitorSampler.parseProcesses(
            "  812  45.3  2.1 123456 WindowServer\n  90 0.0 0.1 2048 Kitty Helper\nbad line\n")
        XCTAssertEqual(processes.map(\.name), ["WindowServer", "Kitty Helper"])
        XCTAssertEqual(processes.first?.cpu, 45.3)
        let monitor = QuickPanelMonitor()
        XCTAssertEqual(monitor.processRows.first?.title, "Processes unavailable")
        monitor.takeSample()
        monitor.takeSample()
        XCTAssertEqual(monitor.cpuHistory.count, 2)
        XCTAssertGreaterThan(monitor.reading.memoryTotal, 0)
    }
}
