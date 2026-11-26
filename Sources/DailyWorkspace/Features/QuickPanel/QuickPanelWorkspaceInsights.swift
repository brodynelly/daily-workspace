import Foundation
import SwiftUI

/// What the workspace page shows about one directory. Every value comes from read-only `git` calls
/// (`--no-optional-locks`, so not even the index is refreshed) or from file existence checks.
struct QuickPanelWorkspaceReport: Equatable, Sendable {
    var path = ""
    var isRepository = false
    var branch = ""
    var upstream = ""
    var ahead = 0
    var behind = 0
    var staged = 0
    var modified = 0
    var untracked = 0
    var conflicts = 0
    var uncommittedAdded = 0
    var uncommittedRemoved = 0
    var lastCommitHash = ""
    var lastCommitSubject: String?
    var lastCommitAge = ""
    /// Commits per day for the last 14 days, oldest first.
    var dailyCommits: [Int] = Array(repeating: 0, count: 14)
    var commits7Days = 0
    var commits30Days = 0
    var agentCommits30Days = 0
    var added7Days = 0
    var removed7Days = 0
    var stashes = 0
    var topFiles: [String]?
    var stack: [String] = []
    var error: String?
}

/// Loads a report for the workspace page; a newer request replaces an older one.
@MainActor
final class QuickPanelWorkspaceInsights: ObservableObject {
    @Published private(set) var report: QuickPanelWorkspaceReport?
    @Published private(set) var loading = false
    private var generation = 0

    /// `private` hides commit subjects and file names, for paths whose contents have their own read policy (the vault).
    func load(path: String, private: Bool) {
        generation += 1
        let current = generation
        loading = true
        report = nil
        Task {
            let result = await QuickPanelWorkspaceReader().report(path: path, hideNames: `private`)
            guard current == self.generation else { return }
            self.report = result
            self.loading = false
        }
    }

    func clear() {
        generation += 1
        report = nil
        loading = false
    }
}

struct QuickPanelWorkspaceReader: Sendable {
    var runner = QuickPanelCommandRunner(timeout: 5, outputLimit: 4 * 1024 * 1024)
    var now: @Sendable () -> Date = { Date() }

    static let agentMarkers = ["claude", "codex", "opencode", "anthropic", "openai", "copilot", "cursor", "gemini"]

    func report(path: String, hideNames: Bool) async -> QuickPanelWorkspaceReport {
        var report = QuickPanelWorkspaceReport(path: path)
        report.stack = Self.stack(at: path)
        guard let status = try? await git(path, ["status", "--porcelain=v2", "--branch"]) else {
            report.error = "Not a Git repository"
            return report
        }
        report.isRepository = true
        Self.applyStatus(status, to: &report)
        if let diff = try? await git(path, ["diff", "--shortstat", "HEAD"]) {
            (report.uncommittedAdded, report.uncommittedRemoved) = Self.parseShortstat(diff)
        }
        if let last = try? await git(path, ["log", "-1", "--format=%h%x1f%s%x1f%cr"]) {
            let parts = last.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
            if parts.count == 3 {
                report.lastCommitHash = parts[0]
                report.lastCommitSubject = hideNames ? nil : parts[1]
                report.lastCommitAge = parts[2]
            }
        }
        if let log = try? await git(path, ["log", "--since=30.days", "--format=%ct%x1f%B%x1e"]) {
            Self.applyLog(log, now: now(), to: &report)
        }
        if let stat = try? await git(path, ["log", "--since=7.days", "--shortstat", "--format="]) {
            (report.added7Days, report.removed7Days) = Self.parseShortstat(stat)
        }
        if let stashes = try? await git(path, ["stash", "list", "--format=%h"]) {
            report.stashes = stashes.split(whereSeparator: \.isNewline).count
        }
        if !hideNames, let names = try? await git(path, ["log", "--since=7.days", "--name-only", "--format="]) {
            report.topFiles = Self.topFiles(names)
        }
        return report
    }

    private func git(_ path: String, _ arguments: [String]) async throws -> String {
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["--no-optional-locks", "-C", path] + arguments,
            environment: ["GIT_TERMINAL_PROMPT": "0", "GIT_PAGER": "cat"])
        guard output.exitStatus == 0 else { throw QuickPanelCommandError.exited(output.exitStatus) }
        return String(bytes: output.stdout, encoding: .utf8) ?? ""
    }

    static func applyStatus(_ text: String, to report: inout QuickPanelWorkspaceReport) {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ")
            if line.hasPrefix("# branch.head "), fields.count >= 3 {
                report.branch = String(fields[2])
            } else if line.hasPrefix("# branch.upstream "), fields.count >= 3 {
                report.upstream = String(fields[2])
            } else if line.hasPrefix("# branch.ab "), fields.count >= 4 {
                report.ahead = Int(fields[2].dropFirst()) ?? 0
                report.behind = Int(fields[3].dropFirst()) ?? 0
            } else if line.hasPrefix("? ") {
                report.untracked += 1
            } else if line.hasPrefix("u ") {
                report.conflicts += 1
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 "), fields.count > 1 {
                let xy = Array(fields[1])
                if xy.count == 2 {
                    if xy[0] != "." { report.staged += 1 }
                    if xy[1] != "." { report.modified += 1 }
                }
            }
        }
    }

    static func applyLog(_ text: String, now: Date, to report: inout QuickPanelWorkspaceReport) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for record in text.components(separatedBy: "\u{1e}") {
            let parts = record.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\u{1f}")
            guard parts.count == 2, let seconds = TimeInterval(parts[0]) else { continue }
            let date = Date(timeIntervalSince1970: seconds)
            report.commits30Days += 1
            let body = parts[1].lowercased()
            if body.split(whereSeparator: \.isNewline).contains(where: { line in
                line.hasPrefix("co-authored-by:") && agentMarkers.contains { line.contains($0) }
            }) {
                report.agentCommits30Days += 1
            }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 99
            if days < 7 { report.commits7Days += 1 }
            if (0..<14).contains(days) { report.dailyCommits[13 - days] += 1 }
        }
    }

    static func parseShortstat(_ text: String) -> (Int, Int) {
        var added = 0
        var removed = 0
        for line in text.split(whereSeparator: \.isNewline) {
            for part in line.split(separator: ",") {
                let words = part.split(separator: " ")
                guard let count = words.first.flatMap({ Int($0) }) else { continue }
                if part.contains("insertion") { added += count }
                if part.contains("deletion") { removed += count }
            }
        }
        return (added, removed)
    }

    static func topFiles(_ text: String, limit: Int = 5) -> [String] {
        var counts: [String: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.isEmpty {
            counts[String(line), default: 0] += 1
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit).map { "\(($0.key as NSString).lastPathComponent) ×\($0.value)" }
    }

    static func stack(at path: String) -> [String] {
        let markers: [(String, String)] = [
            ("Package.swift", "Swift package"), ("package.json", "Node"), ("bun.lock", "Bun"),
            ("Cargo.toml", "Rust"), ("go.mod", "Go"), ("pyproject.toml", "Python"), ("justfile", "just"),
            ("Makefile", "make"), ("AGENTS.md", "AGENTS.md"), ("CLAUDE.md", "CLAUDE.md"),
            (".luuna", "Luuna"),
        ]
        return markers.compactMap { file, label in
            FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(file)) ? label : nil
        }
    }
}

/// The dashboard above a workspace's launch rows.
@MainActor
struct QuickPanelWorkspaceInsightsView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var insights: QuickPanelWorkspaceInsights
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let report = insights.report {
                if report.isRepository {
                    repository(report)
                } else {
                    Text("\(report.error ?? "No Git data") · \(controller.shortPath(report.path))")
                        .foregroundStyle(Ink.meta)
                }
                details(report)
            } else {
                Text(insights.loading ? "Reading workspace…" : "").foregroundStyle(Ink.meta)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace details")
    }

    private func repository(_ report: QuickPanelWorkspaceReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            QuickPanelMonitorBox(title: "branch", trailing: report.stashes > 0 ? "\(report.stashes) stash" : "") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.branch).foregroundStyle(Ink.title).lineLimit(1)
                    Text(
                        report.upstream.isEmpty
                            ? "no upstream" : "↑\(report.ahead) ↓\(report.behind)  \(report.upstream)"
                    )
                    .foregroundStyle(report.ahead + report.behind > 0 ? Ink.gold : Ink.meta)
                    .lineLimit(1)
                }
            }
            QuickPanelMonitorBox(title: "changes") {
                VStack(alignment: .leading, spacing: 4) {
                    let dirty = report.staged + report.modified + report.untracked + report.conflicts
                    Text(dirty == 0 ? "clean" : "\(report.staged) staged · \(report.modified) modified")
                        .foregroundStyle(dirty == 0 ? Ink.cyan : Ink.primary)
                    Text(
                        "\(report.untracked) untracked"
                            + (report.conflicts > 0 ? " · \(report.conflicts) conflicts" : "")
                            + "  +\(report.uncommittedAdded) −\(report.uncommittedRemoved)"
                    )
                    .foregroundStyle(report.conflicts > 0 ? Ink.coral : Ink.meta)
                }
            }
            QuickPanelMonitorBox(title: "14 days", trailing: "\(report.commits7Days) this week") {
                VStack(alignment: .leading, spacing: 4) {
                    QuickPanelSparkGraph(
                        values: report.dailyCommits.map(Double.init),
                        maximum: Double(max(1, report.dailyCommits.max() ?? 1)), length: 14
                    )
                    .frame(height: 22)
                    Text("+\(report.added7Days) −\(report.removed7Days) lines this week").foregroundStyle(Ink.meta)
                }
            }
            QuickPanelMonitorBox(title: "agents", trailing: "30 days") {
                VStack(alignment: .leading, spacing: 4) {
                    let share =
                        report.commits30Days == 0 ? 0 : report.agentCommits30Days * 100 / report.commits30Days
                    Text("\(report.agentCommits30Days)/\(report.commits30Days) co-authored")
                        .foregroundStyle(Ink.primary)
                    QuickPanelMeter(fraction: Double(share) / 100, inverted: true).frame(height: 7)
                    Text("\(share)% agent-assisted").foregroundStyle(Ink.meta)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func details(_ report: QuickPanelWorkspaceReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !report.lastCommitHash.isEmpty {
                line(
                    "last commit",
                    "\(report.lastCommitHash) \(report.lastCommitSubject ?? "") · \(report.lastCommitAge)")
            }
            let running = controller.agentsRunning(in: report.path)
            line(
                "running",
                running.isEmpty
                    ? "no agent sessions here"
                    : running.map { "\($0.title) (\($0.status.isEmpty ? "unknown" : $0.status))" }
                        .joined(separator: " · "))
            if !report.stack.isEmpty { line("stack", report.stack.joined(separator: " · ")) }
            if let files = report.topFiles, !files.isEmpty { line("hot files", files.joined(separator: "  ")) }
        }
    }

    private func line(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).foregroundStyle(Ink.cyan).frame(width: 80, alignment: .leading)
            Text(value).foregroundStyle(Ink.primary).lineLimit(1).truncationMode(.tail)
        }
    }
}
