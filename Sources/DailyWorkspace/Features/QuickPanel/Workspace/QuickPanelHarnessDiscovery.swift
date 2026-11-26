import CryptoKit
import Foundation

extension QuickPanelHarness {
    // MARK: Discovery

    enum ReadFailure: Error {
        case tooLarge(Int), binary, unreadable

        var message: String {
            switch self {
            case .tooLarge(let bytes): "Too large to show here (\(bytes / 1024) KB). o opens it."
            case .binary: "Binary file. o opens it."
            case .unreadable: "Could not read this file."
            }
        }
    }

    nonisolated static func read(_ path: String) -> Result<(String, SHA256Digest), ReadFailure> {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return .failure(.unreadable) }
        guard data.count <= maxEditableBytes else { return .failure(.tooLarge(data.count)) }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { return .failure(.binary) }
        return .success((text, SHA256.hash(data: data)))
    }

    /// Project directories and files that hold agent configuration.
    nonisolated static let projectDirectories = [
        ".claude", ".agents", ".pi", ".codex", ".opencode", ".cursor", ".gemini", ".windsurf", ".github/instructions",
        ".github/prompts",
    ]
    nonisolated static let projectFiles = [
        "AGENTS.md", "CLAUDE.md", "CLAUDE.local.md", "GEMINI.md", ".mcp.json", "opencode.json", "opencode.jsonc",
        ".cursorrules", ".windsurfrules", ".github/copilot-instructions.md",
    ]
    /// Global roots and the children worth showing; everything else there (sessions, caches, history, auth) is
    /// skipped.
    nonisolated static let globalRoots: [(String, [String])] = [
        (
            ".claude",
            [
                "CLAUDE.md", "settings.json", "keybindings.json", "agents", "commands", "skills", "hooks",
                "output-styles",
            ]
        ),
        (".codex", ["AGENTS.md", "config.toml", "hooks.json", "prompts", "skills", "rules"]),
        (".pi/agent", ["AGENTS.md", "settings.json", "mcp.json", "prompts", "skills", "extensions", "themes"]),
        (".agents", ["AGENTS.md", "skills"]),
        (
            ".config/opencode",
            ["opencode.json", "opencode.jsonc", "AGENTS.md", "agent", "agents", "command", "commands"]
        ),
        (".gemini", ["GEMINI.md", "settings.json"]),
    ]
    nonisolated static let skippedDirectories: Set<String> = [
        "worktrees", "node_modules", "projects", "sessions", "cache", "logs", "todos", "shell-snapshots",
        "file-history", "statsig", "telemetry", "paste-cache", "backups", "npm", "bin", "dist", "build",
        "__pycache__", "venv",
    ]
    nonisolated static let textExtensions: Set<String> = [
        "", "md", "markdown", "mdc", "txt", "json", "jsonc", "json5", "toml", "yaml", "yml", "sh", "bash", "zsh",
        "fish", "ts", "js", "mjs", "cjs", "py", "rb", "lua", "rules", "xml", "ini", "cfg", "conf",
    ]

    /// Names that may hold credentials are never listed.
    nonisolated static func isSensitive(_ name: String) -> Bool {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        return lower.hasPrefix("auth") || lower.contains("auth.") || lower.contains("credential")
            || lower.contains("secret") || lower.contains("token") || lower.hasPrefix(".env")
            || lower.contains("keychain") || ["pem", "key", "p12", "pfx", "sqlite", "db", "lock"].contains(ext)
    }

    nonisolated static func discover(project: URL, home: URL, projectReadOnly: Bool) -> [QuickPanelHarnessFile] {
        var result: [QuickPanelHarnessFile] = []
        var seen = Set<String>()
        let root = project.standardizedFileURL
        for file in projectFiles {
            add(root.appendingPathComponent(file), base: root, group: "Project", editable: !projectReadOnly)
        }
        for directory in projectDirectories {
            walk(root.appendingPathComponent(directory), base: root, group: "Project", editable: !projectReadOnly)
        }
        for (relative, children) in globalRoots {
            let base = home.appendingPathComponent(relative).standardizedFileURL
            // A project opened at a global root (e.g. `~/.claude`) is already listed above.
            guard base.path != root.path, !base.path.hasPrefix(root.path + "/") else { continue }
            let group = "~/" + relative
            for child in children {
                let url = base.appendingPathComponent(child)
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { continue }
                if directory.boolValue {
                    walk(url, base: base, group: group, editable: true)
                } else {
                    add(url, base: base, group: group, editable: true)
                }
            }
        }
        return result

        func add(_ url: URL, base: URL, group: String, editable: Bool) {
            guard result.count < maxFiles, !isSensitive(url.lastPathComponent),
                textExtensions.contains(url.pathExtension.lowercased()),
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true
            else { return }
            let resolved = url.resolvingSymlinksInPath().path
            guard seen.insert(resolved).inserted else { return }
            let name = String(url.standardizedFileURL.path.dropFirst(base.path.count + 1))
            result.append(
                .init(id: url.path, group: group, name: name, size: values.fileSize ?? 0, editable: editable))
        }

        func walk(_ directory: URL, base: URL, group: String, editable: Bool) {
            guard
                let enumerator = FileManager.default.enumerator(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
                    options: [.skipsPackageDescendants])
            else { return }
            let baseDepth = directory.pathComponents.count
            var collected: [URL] = []
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if isDirectory {
                    if name.hasPrefix(".") || skippedDirectories.contains(name)
                        || url.pathComponents.count - baseDepth >= 5
                    {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if name.hasPrefix(".") && name != ".mcp.json" { continue }
                collected.append(url)
                if collected.count > maxFiles { break }
            }
            for url in collected.sorted(by: { $0.path < $1.path }) {
                add(url, base: base, group: group, editable: editable)
            }
        }
    }

    /// Masks the value on lines whose key looks like a credential (`"apiKey": "…"`, `TOKEN=…`, `Bearer …`).
    nonisolated static func redacted(_ text: String) -> String {
        let pattern =
            #"(?i)((?:api[_-]?key|apikey|token|secret|password|passwd|authorization|bearer|client[_-]?secret|access[_-]?key)[A-Za-z0-9_\-]*["']?\s*[:=]\s*)(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        var output = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "$1[redacted]")
        if let bearer = try? NSRegularExpression(pattern: #"(?i)(bearer\s+)[A-Za-z0-9._\-]{12,}"#) {
            output = bearer.stringByReplacingMatches(
                in: output, range: NSRange(output.startIndex..., in: output), withTemplate: "$1[redacted]")
        }
        if let keyLike = try? NSRegularExpression(pattern: #"\b(sk|pk|ghp|gho|xox[abp]|AKIA)[-_A-Za-z0-9]{16,}"#) {
            output = keyLike.stringByReplacingMatches(
                in: output, range: NSRange(output.startIndex..., in: output), withTemplate: "[redacted]")
        }
        return output
    }
}
