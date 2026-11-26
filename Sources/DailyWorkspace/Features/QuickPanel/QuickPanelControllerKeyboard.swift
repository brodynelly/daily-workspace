import AppKit
import DailyCore

extension QuickPanelController {
    func handleKey(_ event: NSEvent) -> Bool {
        if event.isARepeat, palette.isVisible {
            return [125, 126, 51, 117].contains(event.keyCode)
                ? handlePaletteKey(keyCode: event.keyCode, characters: "", modifiers: event.modifierFlags) : true
        }
        if event.isARepeat, aiPopup.isVisible {
            return aiPopup.layer == .chat && ![125, 126].contains(event.keyCode)
                ? false
                : handleAIPopupKey(
                    keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                    modifiers: event.modifierFlags)
        }
        if event.isARepeat, focusedPane == "assistant" {
            return false
        }
        if event.isARepeat {
            let modifiers = event.modifierFlags
            if isRepeatableVimKey(event) {
                return handleVimKey(characters: event.charactersIgnoringModifiers ?? "", modifiers: modifiers)
            }
            if !modifiers.contains(.command), !modifiers.contains(.option), !modifiers.contains(.control) {
                if [125, 126, 116, 121, 115, 119].contains(event.keyCode) {
                    return handleSelectionKey(event.keyCode, command: false, shift: modifiers.contains(.shift))
                }
                if currentRoute == .music, [123, 124].contains(event.keyCode) {
                    return handleMusicKey(event.keyCode, character: "", command: false)
                }
                if focusedPane == "command", [123, 124].contains(event.keyCode) { return false }
            }
            // Let the focused search field repeat text/editing keys, not panel actions.
            return
                !(focusedPane == "command"
                && !modifiers.contains(.command)
                && (event.keyCode == 51 || event.keyCode == 117
                    || (!modifiers.contains(.option) && !modifiers.contains(.control)
                        && event.characters?.isEmpty == false
                        && event.characters?.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) == true)))
        }
        return handleKey(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
            modifiers: event.modifierFlags, typedCharacters: event.characters)
    }

    @discardableResult
    func handleKey(
        keyCode: UInt16, characters: String = "", modifiers: NSEvent.ModifierFlags = [],
        typedCharacters: String? = nil
    ) -> Bool {
        if let handled = handleLayerKey(
            keyCode: keyCode, characters: characters, modifiers: modifiers, typedCharacters: typedCharacters)
        {
            return handled
        }
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
        if command && !shift && character == "j" {
            toggleAIPopup()
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
            pendingVimPrefix = nil
            escape()
            return true
        }
        if handleVimKey(
            characters: modifiers.contains(.control) ? characters : typedCharacters ?? characters,
            modifiers: modifiers)
        {
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

    /// Popups, zoom and the AI field get keys before panel shortcuts; `nil` continues normal handling.
    private func handleLayerKey(
        keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags, typedCharacters: String?
    ) -> Bool? {
        if aiPopup.isVisible {
            return handleAIPopupKey(keyCode: keyCode, characters: characters, modifiers: modifiers)
        }
        if let stroke = ShortcutStroke(keyCode: keyCode, characters: characters, modifierFlags: modifiers),
            commandPaletteBinding?.strokes == [stroke]
        {
            toggleCommandPalette()
            return true
        }
        // Music keeps ⌘+ / ⌘- for volume; its zoom is in the ⌘K popup.
        if currentRoute != .music, !modifiers.contains(.shift) || characters == "+",
            handleZoomKey(characters, command: modifiers.contains(.command))
        {
            return true
        }
        if palette.isVisible {
            return handlePaletteKey(
                keyCode: keyCode, characters: typedCharacters ?? characters, modifiers: modifiers)
        }
        if focusedPane == "assistant" {
            return handleAssistantKey(keyCode: keyCode, characters: characters, modifiers: modifiers)
        }
        return nil
    }

    private func handleFallbackKey(_ keyCode: UInt16, characters: String, command: Bool, option: Bool) -> Bool {
        if currentRoute == .music ? handleMusicFunctionKey(keyCode) : handleRouteFunctionKey(keyCode) {
            return true
        }
        if characters == "?", !command, !option, focusedPane != "command" {
            toggleAssistantPane()
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

    var vimPageSize: Int { pageSize }

    private var pageSize: Int {
        // Match QAP's scroll viewport (document pane height minus 34pt insets).
        let height = panel.contentView?.bounds.height ?? panel.frame.height
        let documentBottom = zoomed || !searchVisible ? height - 38 : height - 134
        let documentHeight =
            showsPreview
            ? min(210, max(100, (documentBottom - 40) * 0.45))
            : max(100, documentBottom - 40)
        return max(1, Int(max(0, documentHeight - 34) / 28))
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
        if keyCode == 123, focusedPane != "command" {
            focusedPane = "playlists"
            return true
        }
        if keyCode == 124, focusedPane != "command" {
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
        case 96: performMusic(.volume(-10))
        case 97: performMusic(.volume(10))
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

    func shuffleMusic() {
        performMusic(.shuffle(filteredTrackIDs: rows.compactMap { $0.id.split(separator: ":").last.map(String.init) }))
    }

    func showContextMenu() { showMenu("Context") }

    private func showMenu(_ name: String) {
        openMenuPopup(name)
    }

}
