import Foundation

/// The Git tab's panels, in lazygit order.
enum QuickPanelGitSection: String, CaseIterable, Sendable {
    case files, branches, commits, stash

    var title: String {
        switch self {
        case .files: "Files"
        case .branches: "Branches"
        case .commits: "Commits"
        case .stash: "Stash"
        }
    }
}

struct QuickPanelGitFile: Equatable, Identifiable, Sendable {
    var path: String
    var originalPath: String?
    var index: Character
    var worktree: Character

    var id: String { path }
    var isUntracked: Bool { index == "?" }
    var isConflict: Bool {
        index == "U" || worktree == "U" || (index == "A" && worktree == "A") || (index == "D" && worktree == "D")
    }
    var hasStaged: Bool { !isUntracked && !isConflict && index != " " }
    var hasUnstaged: Bool { isUntracked || worktree != " " }
    var code: String { "\(index)\(worktree)" }
}

struct QuickPanelGitBranch: Equatable, Identifiable, Sendable {
    var name: String
    var isHead: Bool
    var upstream: String
    var age: String
    var subject: String
    var id: String { name }
}

struct QuickPanelGitCommit: Equatable, Identifiable, Sendable {
    var hash: String
    var author: String
    var age: String
    var subject: String
    var id: String { hash }
}

struct QuickPanelGitStash: Equatable, Identifiable, Sendable {
    var ref: String
    var age: String
    var subject: String
    var id: String { ref }
}

struct QuickPanelGitHead: Equatable, Sendable {
    var branch = ""
    var upstream = ""
    var ahead = 0
    var behind = 0
}

/// A destructive operation that runs only after `y`.
enum QuickPanelGitConfirmation: Equatable, Sendable {
    case discard(QuickPanelGitFile)
    case deleteBranch(String)
    case merge(String)
    case dropStash(String)
    case amend

    var prompt: String {
        switch self {
        case .discard(let file):
            file.isUntracked
                ? "Move untracked \(file.path) to the Trash?" : "Discard all changes to \(file.path)?"
        case .deleteBranch(let name): "Delete branch \(name)? (git branch -d, merged branches only)"
        case .merge(let name): "Merge \(name) into the current branch?"
        case .dropStash(let ref): "Drop \(ref)? It cannot be recovered from the stash list."
        case .amend: "Amend the last commit with the staged changes (keeping its message)?"
        }
    }
}

enum QuickPanelGitInput: Equatable, Sendable {
    case commit
    case newBranch

    var prompt: String {
        switch self {
        case .commit: "Commit message"
        case .newBranch: "New branch name"
        }
    }
}

struct QuickPanelGitPreviewLine: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
}

extension QuickPanelGitHub {
    // MARK: Parsing

    nonisolated static func parseStatus(_ text: String) -> (QuickPanelGitHead, [QuickPanelGitFile]) {
        var head = QuickPanelGitHead()
        var files: [QuickPanelGitFile] = []
        var entries = text.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let entry = entries.popFirst() {
            if entry.hasPrefix("## ") {
                head = parseHead(String(entry.dropFirst(3)))
                continue
            }
            let characters = Array(entry)
            guard characters.count > 3 else { continue }
            var file = QuickPanelGitFile(
                path: String(characters[3...]), index: characters[0], worktree: characters[1])
            if "RC".contains(file.index) || "RC".contains(file.worktree) {
                file.originalPath = entries.popFirst()
            }
            files.append(file)
        }
        return (head, files)
    }

    nonisolated static func parseHead(_ line: String) -> QuickPanelGitHead {
        var head = QuickPanelGitHead()
        if line.hasPrefix("No commits yet on ") {
            head.branch = String(line.dropFirst("No commits yet on ".count))
            return head
        }
        if line.hasPrefix("HEAD (no branch)") {
            head.branch = "HEAD"
            return head
        }
        var names = line
        if let bracket = line.range(of: " [") {
            names = String(line[..<bracket.lowerBound])
            let counts = line[bracket.upperBound...].dropLast()
            for part in counts.split(separator: ",") {
                let words = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard words.count == 2, let value = Int(words[1]) else { continue }
                if words[0] == "ahead" { head.ahead = value }
                if words[0] == "behind" { head.behind = value }
            }
        }
        if let dots = names.range(of: "...") {
            head.branch = String(names[..<dots.lowerBound])
            head.upstream = String(names[dots.upperBound...])
        } else {
            head.branch = names
        }
        return head
    }

    nonisolated static func parseBranches(_ text: String) -> [QuickPanelGitBranch] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.components(separatedBy: "\u{1f}")
            guard parts.count == 5 else { return nil }
            return .init(
                name: parts[1], isHead: parts[0] == "*", upstream: parts[2], age: parts[3], subject: parts[4])
        }
    }

    nonisolated static func parseCommits(_ text: String) -> [QuickPanelGitCommit] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.components(separatedBy: "\u{1f}")
            guard parts.count == 4 else { return nil }
            return .init(hash: parts[0], author: parts[1], age: parts[2], subject: parts[3])
        }
    }

    nonisolated static func parseStashes(_ text: String) -> [QuickPanelGitStash] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.components(separatedBy: "\u{1f}")
            guard parts.count == 3 else { return nil }
            return .init(ref: parts[0], age: parts[1], subject: parts[2])
        }
    }

    nonisolated static func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.hasPrefix("/"), !name.hasSuffix("/"),
            !name.hasSuffix(".lock"), !name.hasSuffix("."), !name.contains(".."), !name.contains("@{"),
            !name.contains("//")
        else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.value > 32 && scalar.value != 127 && !"~^:?*[\\".unicodeScalars.contains(scalar)
        }
    }
}

/// Runs `/usr/bin/git -C <repo>` with fixed arguments: no shell, no prompts, no pager.
struct QuickPanelGitClient: Sendable {
    struct Result: Sendable {
        var ok: Bool
        var output: String
        /// A one-line, on-screen summary from git's own output; never logged.
        var message: String
    }

    func run(
        _ path: String, _ arguments: [String], timeout: TimeInterval = 10, network: Bool = false
    ) async -> Result {
        var environment = ["GIT_TERMINAL_PROMPT": "0", "GIT_PAGER": "cat", "GIT_EDITOR": "true", "LC_ALL": "C"]
        if network {
            // Pushing over SSH needs the agent; HTTPS uses the osxkeychain credential helper.
            for name in ["SSH_AUTH_SOCK", "GIT_SSH_COMMAND", "GNUPGHOME"] {
                if let value = ProcessInfo.processInfo.environment[name] { environment[name] = value }
            }
        }
        let runner = QuickPanelCommandRunner(timeout: timeout, outputLimit: 8 * 1024 * 1024)
        do {
            let output = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/git"), arguments: ["-C", path] + arguments,
                environment: environment)
            let stdout = String(bytes: output.stdout, encoding: .utf8) ?? ""
            let summary = Self.summary(output.exitStatus == 0 ? stdout : output.stderrForDisplay + "\n" + stdout)
            return .init(ok: output.exitStatus == 0, output: stdout, message: summary)
        } catch QuickPanelCommandError.timedOut {
            return .init(ok: false, output: "", message: "git timed out after \(Int(timeout))s")
        } catch {
            return .init(ok: false, output: "", message: error.localizedDescription)
        }
    }

    /// The last meaningful line (git prints the outcome last), trimmed for the status line.
    static func summary(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("hint:") }
        let line = lines.first(where: { $0.hasPrefix("error:") || $0.hasPrefix("fatal:") }) ?? lines.last ?? ""
        return String(line.prefix(160))
    }
}
