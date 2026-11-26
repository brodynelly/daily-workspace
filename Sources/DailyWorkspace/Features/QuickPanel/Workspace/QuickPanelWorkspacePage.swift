import Foundation

/// Home's workspace page: Return on a row with a directory opens details and launch rows in the panel;
/// ⌘↵ keeps the row's own action (go to it in Kitty).
extension QuickPanelController {
    func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// The row's directory when it has one that exists; only Home rows open the page on Return.
    func workspaceDetailPath(for row: QuickPanelDataRow) -> String? {
        let path = (row.path as NSString).expandingTildeInPath
        var directory: ObjCBool = false
        guard !path.isEmpty, path.hasPrefix("/"), path.utf8.count <= 4096,
            !path.contains(where: { "\n\r\0".contains($0) }),
            FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue
        else { return nil }
        return (path as NSString).standardizingPath
    }

    func agentsRunning(in path: String) -> [QuickPanelDataRow] {
        dataProvider.snapshot.agents.filter { row in
            !row.path.isEmpty
                && ((row.path as NSString).expandingTildeInPath as NSString).standardizingPath == path
        }
    }

    func openWorkspaceDetail(for row: QuickPanelDataRow, path: String) {
        navigationHistory.append(.init(route: currentRoute, shortcutTool: shortcutTool, workspacePath: workspacePath))
        workspacePath = path
        var rows: [QuickPanelDataRow] = []
        if let action = row.action {
            rows.append(
                .init(
                    id: "detail:go:\(row.id)", title: "Go to \(row.title)", detail: "Switch to it in Kitty",
                    group: "Open", keys: "⌘↵", action: action))
        }
        rows.append(
            .init(
                id: "detail:kitty:\(path)", title: "New Kitty session here", detail: shortPath(path),
                group: "Open", action: .openTarget(path)))
        rows += workspaceLocalRows(path)
        workspaceRows = rows.map { detailRow($0, alternate: row.action) }
        query = ""
        selectedIndex = 0
        updateRows()
        loadWorkspaceInsights(path)
        Task {
            let launches = await dataProvider.workspaceActions(for: path)
            guard workspacePath == path else { return }
            workspaceRows =
                rows.map { detailRow($0, alternate: row.action) }
                + launches.map { launch in
                    var copy = QuickPanelDataRow(
                        id: launch.id, title: launch.action == nil ? launch.title : "Start \(launch.title)",
                        detail: launch.action == nil ? launch.detail : "New agent session in \(shortPath(path))",
                        group: "Agents", action: launch.action)
                    copy.alternate = row.action
                    return copy
                }
            updateRows()
        }
    }

    func loadWorkspaceInsights(_ path: String) {
        insights.load(path: path, private: isVaultPath(path))
    }

    /// Paths inside the selected vault have their own read and write policy.
    func isVaultPath(_ path: String) -> Bool {
        guard let vault = model?.vaultSession.vault?.root.standardizedFileURL.path else { return false }
        return path == vault || path.hasPrefix(vault + "/")
    }

    private func detailRow(_ row: QuickPanelDataRow, alternate: QuickPanelDataAction?) -> QuickPanelDataRow {
        var copy = row
        copy.alternate = alternate
        return copy
    }
}
