import AppKit

/// Terminal-style (vim / lazygit / yazi) normal-mode keys for the Quick Panel.
///
/// They apply whenever the search field is not focused, so plain letters are commands rather than
/// type-to-search; `/` or `?` opens search. Two-key sequences (`gg`, `dd`) use `pendingVimPrefix`.
extension QuickPanelController {
    func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Daily Workspace quick panel"
        alert.informativeText =
            "Vim keys: j/k move, gg/G top/end, ⌃d/⌃u half page, ⌃f/⌃b page, l or Return opens, h goes back, a shows workspace actions, dd dismisses. / searches; ? opens the AI pane (Return asks, Escape closes). 1–0 jump to panels, [ and ] cycle them. r refreshes, z zooms, m opens the menu, q hides. Music: h/l switch panes, Space plays, n/p next/previous, -/+ volume, s shuffles, S plays one at random, x stops. Tab / ⇧Tab changes panes. Escape clears search, hides search, unzooms, hides preview, goes back, then hides. Configure ⌘ shortcuts in Settings → Keyboard."
        alert.runModal()
    }

    /// Routes reached with the number row, in the same order as ⌘1…⌘0.
    static let vimNumberRoutes: [Character: QuickPanelRoute] = [
        "1": .home, "2": .agents, "3": .sessions, "4": .files, "5": .projects,
        "6": .workspaces, "7": .ssh, "8": .tmux, "9": .shortcuts, "0": .music,
    ]

    /// Footer hints; the panel advertises no function keys.
    var vimHints: [(String, String)] {
        if !aiPopup.isVisible, let hints = workspaceTabHints { return hints }
        if aiPopup.isVisible {
            return [
                ("↵", "Ask"), ("/", "Commands"), ("⌘K", "Actions"), ("⇧⌘M", "Model"), ("⌘[ ⌘]", "Questions"),
                ("⌃h ⌃l", "Sections"),
                ("⌘N", "New"), ("⌘+ ⌘-", "Zoom"), ("esc", "Close"),
            ]
        }
        if focusedPane == "command" {
            return [("↑/↓", " Select  "), ("↵", " Open  "), ("Esc", query.isEmpty ? " Close search" : " Clear search")]
        }
        return currentRoute == .music
            ? [
                ("j/k", "Move"), ("h/l", "Panes"), ("␣", "Play"), ("n/p", "Next/Prev"), ("-/+", "Vol"),
                ("s", "Shuffle"), ("/", "Find"), ("?", "AI"), ("⌘J", "Chat"), ("⌘K", "Commands"), ("q", "Hide"),
            ]
            : [
                ("j/k", "Move"), ("l", "Open"), ("h", "Back"), ("/", "Find"), ("?", "AI"), ("⌘J", "Chat"),
                ("1-0", "Panels"),
                ("[ ]", "Prev/Next"), ("r", "Refresh"), ("⌘K", "Commands"), ("q", "Hide"),
            ]
    }

    /// Keys that repeat when held (movement and volume), so `isARepeat` events reach them.
    func isRepeatableVimKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
        guard focusedPane != "command", !modifiers.contains(.command), !modifiers.contains(.option) else {
            return false
        }
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let control = modifiers.contains(.control)
        if control { return ["d", "u", "f", "b", "e", "y"].contains(character) }
        if ["j", "k"].contains(character) { return true }
        return currentRoute == .music && ["-", "=", "+"].contains(character)
    }

    /// Handles one normal-mode key; returns false only when the key is not a vim key at all.
    func handleVimKey(characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard focusedPane != "command", !modifiers.contains(.command), !modifiers.contains(.option) else {
            pendingVimPrefix = nil
            return false
        }
        let control = modifiers.contains(.control)
        guard characters.count == 1, let key = characters.first else {
            pendingVimPrefix = nil
            return false
        }
        if control {
            pendingVimPrefix = nil
            return handleVimControlKey(Character(key.lowercased()))
        }
        if let prefix = pendingVimPrefix {
            pendingVimPrefix = nil
            if completeVimSequence(prefix, key) { return true }
            // An unfinished sequence is dropped; the second key acts on its own.
        }
        if handleVimMotionKey(key) || handleVimCommandKey(key) { return true }
        if let route = Self.vimNumberRoutes[key] {
            navigate(to: route)
            return true
        }
        if currentRoute == .music, handleVimMusicKey(key) { return true }
        if currentRoute == .monitor, ["<", ">", "i"].contains(key) {
            if key == "i" { monitor.reverseSort() } else { monitor.cycleSort(by: key == ">" ? 1 : -1) }
            updateRows()
            return true
        }
        // Swallow other printable keys so a stray letter neither beeps nor starts a search.
        return key.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 0xF700 }
    }

    private func completeVimSequence(_ prefix: Character, _ key: Character) -> Bool {
        switch (prefix, key) {
        case ("g", "g"): moveVimSelection(to: 0)
        case ("d", "d"): activateSelected(remove: true)
        default: return false
        }
        return true
    }

    private func handleVimMotionKey(_ key: Character) -> Bool {
        switch key {
        case "g", "d": pendingVimPrefix = key
        case "j": moveVimSelection(by: 1)
        case "k": moveVimSelection(by: -1)
        case "G": moveVimSelection(to: Int.max)
        case "l":
            if currentRoute == .music { focusedPane = "document" } else { activateSelected() }
        case "h":
            if currentRoute == .music { focusedPane = "playlists" } else { vimBack() }
        default: return false
        }
        return true
    }

    private func handleVimCommandKey(_ key: Character) -> Bool {
        switch key {
        case "o": activateSelected()
        case "a": activateSelected(alternate: true)
        case "/": focusSearch()
        case "?": toggleAIPopup()
        case "[", "]": cycleRoute(reverse: key == "[")
        case "r", "R": refresh()
        case "z": zoomed.toggle()
        case "m", ":": showContextMenu()
        case "q": hide(restoreFocus: true)
        default: return false
        }
        return true
    }

    private func handleVimControlKey(_ key: Character) -> Bool {
        let page = max(1, vimPageSize)
        switch key {
        case "d": moveVimSelection(by: max(1, page / 2))
        case "u": moveVimSelection(by: -max(1, page / 2))
        case "f": moveVimSelection(by: page)
        case "b": moveVimSelection(by: -page)
        case "e": moveVimSelection(by: 1)
        case "y": moveVimSelection(by: -1)
        case "h", "k": cyclePane(reverse: true)
        case "l", "j": cyclePane()
        default: return false
        }
        return true
    }

    private func handleVimMusicKey(_ key: Character) -> Bool {
        switch key {
        case "n": performMusic(.next)
        case "p": performMusic(.previous)
        case "-", "_": performMusic(.volume(-10))
        case "=", "+": performMusic(.volume(10))
        case "s": performMusic(.shuffle(filteredTrackIDs: vimTrackIDs))
        case "S":
            guard let track = rows.randomElement(), let id = track.id.split(separator: ":").last else { return true }
            performMusic(.shuffle(filteredTrackIDs: vimTrackIDs, firstTrackID: String(id), single: true))
        case "x": performMusic(.stop)
        default: return false
        }
        return true
    }

    private var vimTrackIDs: [String] {
        rows.compactMap { $0.id.split(separator: ":").last.map(String.init) }
    }

    /// Moves the playlist column when it has focus in Music, otherwise the result rows.
    private func moveVimSelection(by step: Int) {
        if currentRoute == .music, focusedPane == "playlists" {
            let playlists = music.library?.playlists ?? []
            guard !playlists.isEmpty else { return }
            let current = playlists.firstIndex { $0.id == music.selectedPlaylistID } ?? 0
            selectPlaylist(playlists[min(max(0, current + step), playlists.count - 1)].id)
            return
        }
        select(selectedIndex + step)
    }

    private func moveVimSelection(to index: Int) {
        if currentRoute == .music, focusedPane == "playlists" {
            let playlists = music.library?.playlists ?? []
            guard let target = index == 0 ? playlists.first : playlists.last else { return }
            selectPlaylist(target.id)
            return
        }
        select(index == Int.max ? rows.count - 1 : index)
    }

    /// `h` goes back like Escape, but never hides the panel; use `q` for that.
    private func vimBack() {
        guard !query.isEmpty || zoomed || attentionPreview != nil || !navigationHistory.isEmpty else { return }
        escape()
    }

    private func cycleRoute(reverse: Bool) {
        let routes = QuickPanelRoute.allCases
        let position = routes.firstIndex(of: currentRoute) ?? 0
        navigate(to: routes[(position + (reverse ? routes.count - 1 : 1)) % routes.count])
    }
}
