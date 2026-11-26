import AppKit
import ServiceManagement

extension QuickPanelController {
    func select(_ index: Int) {
        let next = min(max(0, index), max(0, rows.count - 1))
        if next != selectedIndex { attentionPreview = nil }
        selectedIndex = next
        if currentRoute == .attention, rows.indices.contains(next),
            let identity = attentionIdentities[rows[next].id], attentionPreview == nil
        {
            loadAttentionPreview(identity)
        }
    }
    func selectResultFromPointer(_ index: Int) {
        select(index)
        focusedPane = "document"
    }

    func selectPlaylist(_ id: String) {
        music.selectPlaylist(id)
        updateRows()
    }
    func selectPlaylistFromPointer(_ id: String) {
        selectPlaylist(id)
        focusedPane = "playlists"
    }

    func activateSelected(alternate: Bool = false, remove: Bool = false) {
        guard rows.indices.contains(selectedIndex) else { return }
        let row = rows[selectedIndex]
        if currentRoute == .home, workspacePath == nil, !alternate, !remove, let path = workspaceDetailPath(for: row) {
            openWorkspaceDetail(for: row, path: path)
            return
        }
        if workspacePath != nil, !remove, activateWorkspaceLocalRow(row) { return }
        if let runID = row.nativeRunID, !remove {
            model?.luunaWork.selectRun(runID)
            model?.luunaWork.followSelectedRun()
            Task { await model?.luunaWork.refreshSelectedRun() }
            return
        }
        if let identity = attentionIdentities[row.id] {
            activateAttention(identity, alternate: alternate, remove: remove)
            return
        }
        if activateSystem(row, remove: remove) { return }
        if currentRoute == .music, !remove, let id = row.id.split(separator: ":").last,
            let playlist = music.selectedPlaylist
        {
            performMusic(.play(playlistID: playlist.id, trackID: String(id)))
            return
        }
        guard let action = remove ? row.remove : (alternate ? row.alternate ?? row.action : row.action) else { return }
        Task { await executeSelectionAction(action) }
    }

    private func executeSelectionAction(_ action: QuickPanelDataAction) async {
        do {
            reportError(nil)
            switch try await actions.execute(action) {
            case .stay: refresh()
            case .hide:
                try activateKittyIfNeeded(for: action)
                hide(restoreFocus: false)
            case .shortcut(let id):
                if shortcutTool != id {
                    navigationHistory.append(
                        .init(route: currentRoute, shortcutTool: shortcutTool, workspacePath: workspacePath))
                    shortcutTool = id
                    query = ""
                }
                updateRows()
            case .workspace(let path):
                navigationHistory.append(
                    .init(route: currentRoute, shortcutTool: shortcutTool, workspacePath: workspacePath))
                workspacePath = path
                workspaceRows = []
                loadWorkspaceInsights(path)
                let actions = await dataProvider.workspaceActions(for: path)
                guard workspacePath == path else { return }
                workspaceRows = actions
                query = ""
                updateRows()
            }
        } catch { reportError(error.localizedDescription) }
    }

    private func activateKittyIfNeeded(for action: QuickPanelDataAction) throws {
        switch action {
        case .gotoSession, .openFile, .openTarget, .focusAgent:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.kovidgoyal.kitty"),
                NSWorkspace.shared.open(url)
            else { throw QuickPanelDataActionError.unavailable }
        default: break
        }
    }

    private func activateAttention(_ identity: QuickPanelAttentionIdentity, alternate: Bool, remove: Bool) {
        if !remove && !alternate && attentionPreview == nil {
            loadAttentionPreview(identity)
            return
        }
        Task {
            do {
                if remove {
                    try await attention.dismiss(identity)
                    guard currentRoute == .attention else { return }
                    if attention.rows.isEmpty {
                        hide(restoreFocus: true)
                    } else if rows.indices.contains(selectedIndex),
                        attentionIdentities[rows[selectedIndex].id] == identity
                    {
                        attentionPreview = nil
                    }
                } else {
                    try await attention.goToAgent(identity)
                    hide(restoreFocus: false)
                }
            } catch { reportError(error.localizedDescription) }
        }
    }

    private func loadAttentionPreview(_ identity: QuickPanelAttentionIdentity) {
        attentionPreview = "Reading terminal preview…"
        Task {
            do {
                let text = try await attention.preview(identity)
                guard isVisible, currentRoute == .attention, rows.indices.contains(selectedIndex),
                    attentionIdentities[rows[selectedIndex].id] == identity,
                    attentionPreview != nil
                else { return }
                attentionPreview = text
            } catch {
                guard isVisible, currentRoute == .attention, rows.indices.contains(selectedIndex),
                    attentionIdentities[rows[selectedIndex].id] == identity,
                    attentionPreview != nil
                else { return }
                attentionPreview = nil
                reportError(error.localizedDescription)
            }
        }
    }

    private func activateSystem(_ row: QuickPanelDataRow, remove: Bool) -> Bool {
        guard currentRoute == .system, !remove, let name = row.id.split(separator: ":").last,
            let action = QuickPanelSystemAction(rawValue: String(name))
        else { return false }
        Task {
            let result = await systemActions.perform(action)
            guard currentRoute == .system else { return }
            if let message = result.errorMessage { reportError(message) } else { reportError(nil) }
            if result == .completed { hide(restoreFocus: false) }
        }
        return true
    }

    func performMusic(_ action: QuickPanelMusicAction) {
        onMusicAction?(action)
        Task {
            do {
                try await music.perform(action)
                updateRows()
                reportError(nil)
            } catch { reportError(error.localizedDescription) }
        }
    }

    func escape() {
        if !query.isEmpty {
            query = ""
            return
        }
        if focusedPane == "command" {
            focusedPane = "document"
            return
        }
        if zoomed {
            zoomed = false
            return
        }
        if attentionPreview != nil {
            attentionPreview = nil
            return
        }
        if let previous = navigationHistory.popLast() {
            currentRoute = previous.route
            shortcutTool = previous.shortcutTool
            workspacePath = previous.workspacePath
            music.setVisible(isVisible && currentRoute == .music)
            if isVisible && currentRoute == .music { reloadMusic() }
            if previous.route == .calendar { loadCalendar() } else { updateRows() }
            return
        }
        hide(restoreFocus: true)
    }

    func cyclePane(reverse: Bool = false) {
        if zoomed {
            focusedPane = "document"
            return
        }
        let panes =
            (currentRoute == .music ? ["playlists"] : [])
            + ["document", "command"]
        let position = panes.firstIndex(of: focusedPane) ?? 0
        focusedPane = panes[(position + (reverse ? panes.count - 1 : 1)) % panes.count]
    }

    func focusSearch() {
        focusedPane = "command"
        searchRequest += 1
    }

    static func mouseTarget(position: String, visibleFrame: CGRect, primaryScreenMaxY: CGFloat) -> CGPoint? {
        guard !visibleFrame.isEmpty, position == "center" || position == "corner" else { return nil }
        let point: CGPoint
        if position == "corner" {
            point = CGPoint(
                x: visibleFrame.maxX - min(100, max(0, visibleFrame.width - 1)),
                y: visibleFrame.minY + min(100, max(0, visibleFrame.height - 1)))
        } else {
            point = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        }
        return CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    func handleControlAction(_ action: QuickPanelControlAction) -> [String: Any] {
        if case .login(let mode) = action { return handleLoginControl(mode) }
        switch action {
        case .show, .toggle, .hide:
            handlePanelVisibility(action)
        case .refresh: refresh()
        case .attentionRefresh: Task { await attention.refresh() }
        case .paletteChanged: installBackground()
        case .status, .inspect, .clipboard, .login: break
        case .quit: DispatchQueue.main.async { NSApp.terminate(nil) }
        case .mouse(let position):
            if let screen = NSScreen.main,
                let point = Self.mouseTarget(
                    position: position, visibleFrame: screen.visibleFrame,
                    primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY)
            {
                CGWarpMouseCursorPosition(point)
            }
        }
        var response: [String: Any] = [
            "ok": true,
            "visible": isVisible, "view": currentRoute.rawValue, "query": query,
            "rows": rows.count, "selected": rows.isEmpty ? -1 : selectedIndex,
            "ready": true, "layout": "pascal-panes", "focus_pane": focusedPane,
            "music_preview": music.preview, "font": panelFont,
            "preview_visible": attentionPreview != nil,
        ]
        if clipboardFeedbackEnabled {
            response["clipboard_change_count"] = NSPasteboard.general.changeCount
        }
        return response
    }

    private func handleLoginControl(_ mode: String) -> [String: Any] {
        let service = SMAppService.mainApp
        do {
            if mode == "enable", service.status != .enabled && service.status != .requiresApproval {
                try service.register()
            } else if mode == "disable", service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            let status: String
            switch service.status {
            case .enabled: status = "enabled"
            case .requiresApproval: status = "requiresApproval"
            case .notRegistered: status = "notRegistered"
            case .notFound: status = "notFound"
            @unknown default: status = "unknown"
            }
            return ["ok": true, "login": status]
        } catch {
            return ["ok": false, "error": "Could not change Start at login: \(error.localizedDescription)"]
        }
    }

    private func handlePanelVisibility(_ action: QuickPanelControlAction) {
        switch action {
        case .show(let route): show(route)
        case .toggle(let route): toggle(route)
        case .hide: hide(restoreFocus: true)
        default: break
        }
    }

    func navigate(to route: QuickPanelRoute) {
        if currentRoute != route || shortcutTool != nil || workspacePath != nil {
            navigationHistory.append(
                .init(route: currentRoute, shortcutTool: shortcutTool, workspacePath: workspacePath))
        }
        reportError(nil)
        currentRoute = route
        shortcutTool = nil
        workspacePath = nil
        attentionPreview = nil
        focusedPane = "document"
        query = ""
        music.setVisible(isVisible && route == .music)
        if route == .music && isVisible { reloadMusic() }
        if route == .calendar { loadCalendar() }
        updateRows()
    }

    func refresh() {
        reportError(nil)
        refreshGeneration += 1
        let generation = refreshGeneration
        Task { [weak self] in
            guard let self else { return }
            await self.dataProvider.refresh()
            guard generation == self.refreshGeneration else { return }
            self.updateRows()
        }
        if currentRoute == .attention { Task { await attention.refresh() } }
        if currentRoute == .agents { Task { await model?.luunaWork.refresh() } }
        if currentRoute == .calendar { loadCalendar() }
        if currentRoute == .music { reloadMusic() }
    }
}
