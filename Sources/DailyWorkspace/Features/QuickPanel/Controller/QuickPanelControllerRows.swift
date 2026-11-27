import DailyCore
import Foundation

extension QuickPanelController {
    func updateRows() {
        let previous = rows.indices.contains(selectedIndex) ? rows[selectedIndex].id : nil
        attentionIdentities = [:]
        let source = sourceRows()
        let filter = QuickPanelSearch.Query(query)
        rows = source.filter { row in
            filter.matches(
                .init(
                    title: row.title, detail: row.detail, group: row.group,
                    badge: row.badge, keys: row.keys, keywords: row.keywords,
                    keyNames: row.keyNames))
        }
        if !query.isEmpty, let typed = quickPanelTypedDirectoryRow(query, for: currentRoute) {
            rows.append(typed)
        }
        let retained = previous.flatMap { id in rows.firstIndex(where: { $0.id == id }) }
        if retained == nil { attentionPreview = nil }
        selectedIndex = retained ?? 0
        // The attention watcher can open the panel without a keyboard selection event.
        // Populate the selected row's preview once the panel is visible, not at startup.
        if isVisible, currentRoute == .attention, attentionPreview == nil {
            select(selectedIndex)
        }
    }
    private func sourceRows() -> [QuickPanelDataRow] {
        switch currentRoute {
        case .agents:
            let existing =
                query.isEmpty
                ? dataProvider.snapshot.rows(for: .agents)
                : dataProvider.snapshot.searchRows(for: .agents)
            return existing + nativeRunRows()

        case .attention:
            return attentionRows()
        case .monitor:
            return monitor.processRows
        case .system:
            return QuickPanelSystemAction.allCases.map { action in
                .init(id: "system:\(action.rawValue)", title: action.title, detail: action.detail, group: "System")
            }
        case .music:
            return (music.selectedPlaylist?.tracks ?? []).map { track in
                .init(
                    id: "music:\(track.id)", title: track.name, detail: "\(track.artist) · \(track.album)",
                    group: "Music", badge: track.timeLabel, musicArtist: track.artist, musicAlbum: track.album)
            }
        case .calendar:
            guard case .some(.agenda(let events, _)) = calendarSnapshot else { return [] }
            return events.map { event in
                .init(
                    id: "calendar:\(event.id)", title: event.title,
                    detail: event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened),
                    group: "Apple Calendar")
            }
        default:
            if workspacePath != nil { return workspaceRows }
            return query.isEmpty
                ? dataProvider.snapshot.rows(for: currentRoute, shortcutTool: shortcutTool)
                : dataProvider.snapshot.searchRows(for: currentRoute, shortcutTool: shortcutTool)
        }
    }

    private func nativeRunRows() -> [QuickPanelDataRow] {
        guard let model else { return [] }
        let work = model.luunaWork
        guard let binding = work.observedProjectBinding else {
            let reason = LuunaStatusWords.describe(work.runs.state, origin: model.luuna.origin)
            return [
                .init(
                    id: "luuna:binding", title: "Luuna runs not selected",
                    detail: work.runs.state == .unauthorized
                        ? reason.text : "Select a project bound to this runtime in Projects",
                    group: "Luuna runs")
            ]
        }
        let words = LuunaStatusWords.describe(work.runs.state, origin: model.luuna.origin)
        let rows = (work.runs.value ?? []).map { run in
            QuickPanelDataRow(
                id: "luuna:run:\(binding.projectID):\(run.id)", title: run.id,
                detail: "Project \(binding.projectID) · run state \(run.state.rawValue)"
                    + (work.runs.isShowingRetainedValue ? " · stale" : ""),
                group: "Luuna runs", badge: run.state.rawValue, nativeRunID: run.id,
                status: run.state.rawValue)
        }
        if !work.runs.state.isSuccess || rows.isEmpty {
            return rows + [
                .init(
                    id: "luuna:runs:state", title: "Luuna runs: \(words.text)",
                    detail: "Project \(binding.projectID)", group: "Luuna runs")
            ]
        }
        return rows
    }

    private func attentionRows() -> [QuickPanelDataRow] {
        let source: [QuickPanelDataRow] = attention.rows.map { item in
            let id =
                "attention:\(item.agent.id):\(item.agent.generation):\(item.agent.instance.utf8.count):\(item.agent.instance):\(item.agent.reason)"
            attentionIdentities[id] = item.id
            return .init(
                id: id, title: item.agent.displayTitle, detail: item.agent.cwd,
                group: "Attention · \(item.agent.kindLabel)", badge: item.agent.reason,
                status: item.agent.status)
        }
        guard source.isEmpty else { return source }
        let message: String
        switch attention.sourceState {
        case .notRead: message = "Loading attention inventory"
        case .missing: message = "Attention inventory missing"
        case .unavailable: message = "Attention inventory unreadable"
        case .invalid: message = "Attention inventory invalid"
        case .empty, .populated: message = "No agents asking for attention"
        }
        return [
            .init(
                id: "attention-status", title: message, detail: "SketchyBar agent inventory",
                group: "Attention")
        ]
    }

}
