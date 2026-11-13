import AppKit
import DailyCore

extension QuickPanelController {
    func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Daily Workspace quick panel"
        alert.informativeText =
            "Tab / ⇧Tab changes panes. Arrows select; Return opens. Escape clears search, unzooms, hides preview, goes back, then hides. ⌘W hides directly. Configure panel routes, search, refresh, help and zoom in Settings → Keyboard. F2/F4–F8 navigate in Workspace or control playback in Music. ⌥F/E/P/S/W/H opens a menu."
        alert.runModal()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        return handleKey(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
            modifiers: event.modifierFlags, typedCharacters: event.characters)
    }

    @discardableResult
    func handleKey(
        keyCode: UInt16, characters: String = "", modifiers: NSEvent.ModifierFlags = [],
        typedCharacters: String? = nil
    ) -> Bool {
        if let stroke = ShortcutStroke(keyCode: keyCode, characters: characters, modifierFlags: modifiers),
            handleConfiguredShortcut(stroke)
        {
            return true
        }
        let command = modifiers.contains(.command)
        let option = modifiers.contains(.option)
        let shift = modifiers.contains(.shift)
        let character = characters.lowercased()
        if command && character == "w" {
            hide(restoreFocus: true)
            return true
        }
        if option,
            let menu = [
                "f": "File", "e": "Edit", "p": "Play", "v": "View",
                "s": "Shuffle", "w": "Window", "h": "Help",
            ][character]
        {
            showMenu(menu)
            return true
        }
        if keyCode == 53 {
            escape()
            return true
        }
        if handleSelectionKey(keyCode, command: command, shift: shift) {
            return true
        }
        if currentRoute == .music, handleMusicKey(keyCode, character: character, command: command) {
            return true
        }
        return handleFallbackKey(
            keyCode, characters: typedCharacters ?? characters, command: command, option: option)
    }

    private func handleFallbackKey(_ keyCode: UInt16, characters: String, command: Bool, option: Bool) -> Bool {
        if currentRoute == .music ? handleMusicFunctionKey(keyCode) : handleRouteFunctionKey(keyCode) {
            return true
        }
        guard !command, !option, !characters.isEmpty,
            characters.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }),
            focusedPane != "command"
        else { return false }
        query += characters
        focusedPane = "command"
        return true
    }

    private func handleConfiguredShortcut(_ stroke: ShortcutStroke) -> Bool {
        for definition in KeyboardShortcutCatalog.definitions where definition.context == .quickPanel {
            let binding: ShortcutBinding?
            if let model {
                binding = KeyboardShortcutCatalog.binding(for: definition.id, preferences: model.preferences)
            } else {
                binding = definition.defaultBinding
            }
            guard let binding, binding.strokes.count == 1, binding.strokes[0] == stroke else { continue }
            if definition.id == "panel.refreshFunction", stroke.key == "f9", currentRoute == .music { continue }
            return performConfiguredShortcut(definition.id)
        }
        return false
    }

    private func performConfiguredShortcut(_ id: String) -> Bool {
        switch id {
        case "panel.find", "panel.findFunction": focusSearch()
        case "panel.refresh", "panel.refreshFunction": refresh()
        case "panel.hide": hide(restoreFocus: true)
        case "panel.actions": activateSelected(alternate: true)
        case "panel.zoom": zoomed.toggle()
        case "panel.help": showHelp()
        case "panel.contextMenu": showMenu("Context")
        default:
            guard let route = QuickPanelRoute(rawValue: String(id.dropFirst("panel.".count))) else {
                return false
            }
            navigate(to: route)
        }
        return true
    }

    private func handleSelectionKey(_ keyCode: UInt16, command: Bool, shift: Bool) -> Bool {
        if command && [51, 117].contains(keyCode) {
            activateSelected(remove: true)
            return true
        }
        if currentRoute == .music, focusedPane == "playlists" {
            if [36, 76].contains(keyCode) {
                guard !command else { return false }
                focusedPane = "document"
                return true
            }
            if movePlaylistSelection(keyCode) { return true }
        }
        if [36, 76].contains(keyCode) {
            guard !command else { return false }
            activateSelected()
            return true
        }
        if keyCode == 48 {
            cyclePane(reverse: shift)
            return true
        }
        return moveSelection(keyCode)
    }

    private func moveSelection(_ keyCode: UInt16) -> Bool {
        let step: Int
        switch keyCode {
        case 125: step = 1
        case 126: step = -1
        case 116: step = -pageSize
        case 121: step = pageSize
        case 115:
            select(0)
            return true
        case 119:
            select(rows.count - 1)
            return true
        default: return false
        }
        select(selectedIndex + step)
        return true
    }

    private var pageSize: Int {
        // Match the visible document list: pane insets, 27-point header and 28-point rows.
        let height = panel.contentView?.bounds.height ?? panel.frame.height
        let documentHeight =
            showsPreview ? min(210, max(100, (height - 174) * 0.45)) : height - (zoomed ? 78 : 174)
        return max(1, Int(max(0, documentHeight - 60) / 28))
    }

    private var playlistPageSize: Int {
        let height = panel.contentView?.bounds.height ?? panel.frame.height
        return max(1, Int(max(0, height - 111) / 28))
    }

    private func movePlaylistSelection(_ keyCode: UInt16) -> Bool {
        let step: Int
        switch keyCode {
        case 125: step = 1
        case 126: step = -1
        case 116: step = -playlistPageSize
        case 121: step = playlistPageSize
        case 115, 119: step = 0
        default: return false
        }
        let playlists = music.library?.playlists ?? []
        guard !playlists.isEmpty else { return true }
        let current = playlists.firstIndex { $0.id == music.selectedPlaylistID } ?? 0
        let next: Int
        switch keyCode {
        case 115: next = 0
        case 119: next = playlists.count - 1
        default: next = min(max(0, current + step), playlists.count - 1)
        }
        selectPlaylist(playlists[next].id)
        return true
    }

    private func handleMusicKey(_ keyCode: UInt16, character: String, command: Bool) -> Bool {
        if keyCode == 123 {
            focusedPane = "playlists"
            return true
        }
        if keyCode == 124 {
            focusedPane = "document"
            return true
        }
        if keyCode == 49 && focusedPane != "command" {
            performMusic(.playPause)
            return true
        }
        if command && ["+", "=", "-"].contains(character) {
            performMusic(.volume(character == "-" ? -5 : 5))
            return true
        }
        return false
    }

    private func handleMusicFunctionKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 120: randomMusic()
        case 118: shuffleMusic()
        case 96: performMusic(.volume(-5))
        case 97: performMusic(.volume(5))
        case 98: performMusic(.previous)
        case 100: performMusic(.playPause)
        case 101: performMusic(.next)
        default: return false
        }
        return true
    }

    private func handleRouteFunctionKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 120: navigate(to: .agents)
        case 118: navigate(to: .projects)
        case 96: navigate(to: .sessions)
        case 97: navigate(to: .files)
        case 98: navigate(to: .workspaces)
        case 100: navigate(to: .shortcuts)
        default: return false
        }
        return true
    }

    private func randomMusic() {
        guard let track = rows.randomElement(), let id = track.id.split(separator: ":").last else { return }
        performMusic(
            .shuffle(
                filteredTrackIDs: rows.compactMap { $0.id.split(separator: ":").last.map(String.init) },
                firstTrackID: String(id), single: true))
    }

    private func shuffleMusic() {
        performMusic(.shuffle(filteredTrackIDs: rows.compactMap { $0.id.split(separator: ":").last.map(String.init) }))
    }

    private func showMenu(_ name: String) {
        panelMenu(named: name).popUp(
            positioning: nil, at: NSPoint(x: 12, y: panel.frame.height - 32),
            in: panel.contentView)
    }

    func panelMenu(named name: String) -> NSMenu {
        let menu = NSMenu(title: name)
        if name == "Context" {
            for heading in ["File", "Edit", currentRoute == .music ? "Play" : "View", "Shuffle", "Window", "Help"] {
                let item = NSMenuItem(title: heading, action: nil, keyEquivalent: "")
                item.submenu = panelMenu(named: heading)
                menu.addItem(item)
            }
            return menu
        }
        let choices: [(String, String)]
        switch name {
        case "File":
            choices = [
                ("Open selection", "open"), ("Workspace actions", "alternate"),
                ("Quick AI Chat", "assistant"), ("Dismiss / Close session", "remove"),
                ("Refresh", "refresh"),
                ("Close panel", "close"),
            ]
        case "Edit":
            choices = [("Clear search", "clear"), ("Find", "find"), ("Back", "back")]
        case "Play", "Shuffle":
            if currentRoute == .music {
                choices = [
                    ("Play / Pause", "playpause"), ("Stop", "stop"),
                    ("Previous track", "previous"), ("Next track", "next"),
                    ("Shuffle", "shuffle"), ("End Shuffle", "endShuffle"),
                    ("Volume down", "volumeDown"), ("Volume up", "volumeUp"),
                ]
            } else {
                choices = QuickPanelRoute.allCases.map { ($0.title, "route:\($0.rawValue)") }
            }
        case "Help":
            choices = [("Quick panel help", "help")]
        default:
            choices = QuickPanelRoute.allCases.map { ($0.title, "route:\($0.rawValue)") }
        }
        for (title, command) in choices {
            let item = NSMenuItem(title: title, action: #selector(performPanelMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command
            menu.addItem(item)
        }
        return menu
    }

    @objc private func performPanelMenu(_ item: NSMenuItem) {
        guard let action = item.representedObject as? String else { return }
        switch action {
        case "assistant", "clear", "find", "back", "help":
            performPanelNavigationMenu(action)
        case "open": activateSelected()
        case "alternate": activateSelected(alternate: true)
        case "remove": activateSelected(remove: true)
        case "refresh": refresh()
        case "close": hide(restoreFocus: true)
        case "playpause", "stop", "previous", "next", "shuffle", "endShuffle", "volumeDown", "volumeUp":
            performPanelMusicMenu(action)
        default:
            guard action.hasPrefix("route:"),
                let route = QuickPanelRoute(rawValue: String(action.dropFirst(6)))
            else { return }
            navigate(to: route)
        }
    }

    private func performPanelNavigationMenu(_ action: String) {
        switch action {
        case "assistant": open(.assistant)
        case "clear": query = ""
        case "find": focusSearch()
        case "back": escape()
        case "help": showHelp()
        default: break
        }
    }

    private func performPanelMusicMenu(_ action: String) {
        switch action {
        case "playpause": performMusic(.playPause)
        case "stop": performMusic(.stop)
        case "previous": performMusic(.previous)
        case "next": performMusic(.next)
        case "shuffle": shuffleMusic()
        case "endShuffle": performMusic(.endShuffle)
        case "volumeDown": performMusic(.volume(-5))
        case "volumeUp": performMusic(.volume(5))
        default: break
        }
    }
}
