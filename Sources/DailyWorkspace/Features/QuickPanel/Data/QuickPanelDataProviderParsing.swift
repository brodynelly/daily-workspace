import Foundation

extension QuickPanelDataProvider {
    func parseKitty(_ data: Data, into result: inout QuickPanelDataSnapshot) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let kitty = root["kitty"] as? Bool,
            let agents = root["agents"] as? [Any],
            let sessions = root["sessions"] as? [Any],
            let files = root["files"] as? [Any]
        else {
            result.notices.append("Invalid Kitty sessions response")
            result.agents = [.unavailable("Agents", "Invalid Kitty response")]
            result.sessions = [.unavailable("Sessions", "Invalid Kitty response")]
            result.files = [.unavailable("Files", "Invalid Kitty response")]
            return
        }
        result.agents = agents.compactMap { value -> QuickPanelDataRow? in
            guard let item = value as? [String: Any] else { return nil }
            guard let id = item["id"] as? NSNumber, id.int64Value > 0,
                let title = nonempty(item, "opencode_title") ?? nonempty(item, "title")
            else { return nil }
            var row = QuickPanelDataRow(
                id: "agent:\(id.uint64Value)", title: title,
                detail: short(item["cwd"] as? String ?? ""), group: "Agents", action: .focusAgent(id.uint64Value))
            row.path = item["cwd"] as? String ?? ""
            row.badge = item["kind_label"] as? String ?? ""
            row.status = item["status"] as? String ?? ""
            row.keys =
                row.status == "attention"
                ? "needs attention · \(item["reason"] as? String ?? "")"
                : row.status
            return row
        }
        result.sessions = sessions.compactMap { value -> QuickPanelDataRow? in
            guard let item = value as? [String: Any] else { return nil }
            guard let name = nonempty(item, "name") else { return nil }
            var row = QuickPanelDataRow(
                id: "session:\(name)", title: name,
                detail: short(item["path"] as? String ?? ""), group: "Sessions", action: .gotoSession(name))
            let tabs = max(0, (item["tabs"] as? Int) ?? 0)
            row.badge = "\(tabs) tabs" + ((item["current"] as? Bool) == true ? " · current" : "")
            row.status = item["agent_status"] as? String ?? ""
            row.keys = keyString(item["keys"])
            row.path = item["path"] as? String ?? ""
            row.remove = .closeSession(name)
            return row
        }
        result.files = files.compactMap { value -> QuickPanelDataRow? in
            guard let item = value as? [String: Any] else { return nil }
            guard let name = nonempty(item, "name"), let path = nonempty(item, "path") else { return nil }
            var row = QuickPanelDataRow(
                id: "file:\(path)", title: name,
                detail: short(path), group: "Files", action: .openFile(path))
            row.keys = keyString(item["keys"])
            row.badge = (item["open"] as? Bool) == true ? "open" : ""
            return row
        }
        if !kitty {
            result.notices.append("Kitty is not running")
            result.agents = [.unavailable("Agents", "Kitty is not running")]
            result.sessions = [.unavailable("Sessions", "Kitty is not running")]
        }
    }

    func parseTargets(_ data: Data, into result: inout QuickPanelDataSnapshot) {
        guard let text = String(data: data, encoding: .utf8) else {
            result.notices.append("Invalid targets response")
            result.projects = [.unavailable("Projects", "Invalid targets response")]
            result.ssh = [.unavailable("SSH", "Invalid targets response")]
            result.tmux = [.unavailable("tmux", "Invalid targets response")]
            return
        }
        for line in text.split(whereSeparator: \.isNewline) {
            let target = String(line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            guard !target.isEmpty else { continue }
            if target.hasPrefix("ssh:") {
                let name = String(target.dropFirst(4))
                guard !name.isEmpty else { continue }
                result.ssh.append(
                    .init(
                        id: "target:\(target)", title: name, detail: target,
                        group: "SSH", action: .openTarget(target)))
            } else if target.hasPrefix("tmux:") {
                let name = String(target.dropFirst(5))
                guard !name.isEmpty else { continue }
                result.tmux.append(
                    .init(
                        id: "target:\(target)", title: name, detail: target,
                        group: "tmux", action: .openTarget(target)))
            } else if target.hasPrefix("/") {
                var row = QuickPanelDataRow(
                    id: "target:\(target)",
                    title: URL(fileURLWithPath: target).lastPathComponent, detail: short(target),
                    group: "Projects", keys: "⌘↵ launch", action: .openTarget(target))
                row.alternate = .workspaceActions(target)
                result.projects.append(row)
            }
        }
    }

    func parseWorkspaceCatalog(_ data: Data, into result: inout QuickPanelDataSnapshot) {
        guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            result.notices.append("Invalid workspace catalog response")
            result.workspaces = [.unavailable("Workspaces", "Invalid workspace catalog")]
            return
        }
        result.workspaces = entries.compactMap { entry -> QuickPanelDataRow? in
            guard let entry = entry as? [String: Any], let name = nonempty(entry, "name"),
                let path = nonempty(entry, "path"), path.hasPrefix("/"), path.utf8.count <= 4096,
                !path.contains(where: { "\n\r\0".contains($0) })
            else { return nil }
            return .init(
                id: "workspace:\(path)", title: name, detail: short(path),
                group: "Workspaces", action: .workspaceActions(path))
        }
        if result.workspaces.count != entries.count {
            result.notices.append("Invalid workspace catalog entries skipped")
        }
        if result.workspaces.isEmpty {
            result.workspaces = [
                .unavailable("Workspaces", entries.isEmpty ? "No workspaces in catalog" : "Invalid workspace catalog")
            ]
        }
    }

    func reloadShortcuts() {
        let (tools, entries) = shortcutRows()
        snapshot.shortcutTools = tools
        snapshot.shortcutEntries = entries
    }

    func shortcutRows() -> ([QuickPanelDataRow], [String: [QuickPanelDataRow]]) {
        guard let index = jsonShortcut("index.json") as? [String: Any],
            let groups = index["groups"] as? [Any]
        else {
            return ([.unavailable("Shortcuts", "Shortcut index unavailable")], [:])
        }
        var tools: [QuickPanelDataRow] = []
        var entries: [String: [QuickPanelDataRow]] = [:]
        for value in groups {
            guard let group = value as? [String: Any], let members = group["tools"] as? [Any] else { continue }
            for value in members {
                guard let tool = value as? [String: Any] else { continue }
                guard let id = nonempty(tool, "id"), safeShortcutID(id),
                    let title = nonempty(tool, "title")
                else { continue }
                var row = QuickPanelDataRow(
                    id: "shortcut:\(id)", title: title,
                    detail: tool["subtitle"] as? String ?? "", group: group["title"] as? String ?? "Shortcuts",
                    action: .shortcutTool(id))
                row.keys = "↵"
                tools.append(row)
                entries[id] = shortcutEntries(id: id, title: title)
            }
        }
        return tools.isEmpty ? ([.unavailable("Shortcuts", "No shortcut tools available")], [:]) : (tools, entries)
    }

    private func shortcutEntries(id: String, title: String) -> [QuickPanelDataRow] {
        let sections = (jsonShortcut("\(id).json") as? [String: Any])?["sections"] as? [Any] ?? []
        return sections.flatMap { value -> [QuickPanelDataRow] in
            guard let section = value as? [String: Any] else { return [] }
            let sectionTitle = section["title"] as? String ?? ""
            return (section["rows"] as? [Any] ?? []).enumerated().compactMap { index, value in
                guard let item = value as? [String: Any], let label = nonempty(item, "label") else { return nil }
                var detail = "\(title) / \(sectionTitle)"
                if let note = nonempty(item, "note") { detail += " · \(note)" }
                var entry = QuickPanelDataRow(
                    id: "shortcut:\(id):\(sectionTitle):\(index)",
                    title: label, detail: detail, group: id, action: .shortcutTool(id))
                entry.keys = keyString(item["keys"])
                (entry.keywords, entry.keyNames) = shortcutSearchKeys(item["keys"])
                return entry
            }
        }
    }

    private func jsonShortcut(_ file: String) -> Any? {
        guard file == "index.json" || (file.hasSuffix(".json") && safeShortcutID(String(file.dropLast(5)))) else {
            return nil
        }
        for directory in [dotfiles.appendingPathComponent("hammerspoon/shortcuts"), bundledShortcuts] {
            let path = directory.appendingPathComponent(file)
            guard path.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/"),
                let size = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size]) as? NSNumber,
                size.intValue <= 1_048_576, let data = try? Data(contentsOf: path),
                let json = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            return json
        }
        return nil
    }

    private func safeShortcutID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy(asciiIdentifier)
    }

    func asciiIdentifier(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 95
    }

    func short(_ path: String) -> String {
        let prefix = home.path
        return path == prefix ? "~" : path.hasPrefix(prefix + "/") ? "~" + String(path.dropFirst(prefix.count)) : path
    }
}
