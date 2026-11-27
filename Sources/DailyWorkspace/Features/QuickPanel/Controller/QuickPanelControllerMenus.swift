import AppKit

extension QuickPanelController {
    var menuHeadings: [String] {
        ["File", "Edit"] + (currentRoute == .music ? ["Play", "Shuffle"] : ["View"]) + ["Window", "Help"]
    }

    func panelMenu(named name: String) -> NSMenu {
        let menu = NSMenu(title: name)
        if name == "Context" {
            for heading in menuHeadings {
                let item = NSMenuItem(title: heading, action: nil, keyEquivalent: "")
                item.submenu = panelMenu(named: heading)
                menu.addItem(item)
            }
            return menu
        }
        for (title, command) in menuChoices(named: name) {
            let item = NSMenuItem(title: title, action: #selector(performPanelMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command
            menu.addItem(item)
        }
        return menu
    }

    func menuChoices(named name: String) -> [(title: String, command: String)] {
        let choices: [(String, String)]
        switch name {
        case "File":
            let workspace =
                currentRoute.workspaceSection.map { [("Open \($0.title) in Daily Workspace", "workspace")] } ?? []
            choices =
                workspace + [
                    ("Open selection", "open"), ("Workspace actions", "alternate"),
                    ("Quick AI Chat", "assistant"), ("Dismiss / Close session", "remove"),
                    ("Refresh", "refresh"),
                    ("Close panel", "close"),
                ]
        case "Edit":
            choices = [
                ("Find in panel", "find"), ("Clear search", "clear"), ("Back", "back"), ("Go to Home", "route:home"),
            ]
        case "Play":
            if currentRoute == .music {
                choices = [
                    ("Play / Pause", "playpause"), ("Stop", "stop"),
                    ("Previous track", "previous"), ("Next track", "next"),
                    ("Volume down", "volumeDown"), ("Volume up", "volumeUp"),
                ]
            } else {
                choices = QuickPanelRoute.allCases.map { ($0.title, "route:\($0.rawValue)") }
            }
        case "Shuffle":
            choices =
                currentRoute == .music
                ? [("Shuffle", "shuffle"), ("End Shuffle", "endShuffle")]
                : QuickPanelRoute.allCases.map { ($0.title, "route:\($0.rawValue)") }
        case "View":
            choices = [
                ("Find in panel", "find"), (zoomed ? "Unzoom" : "Zoom", "zoom"), ("Command palette…", "palette"),
            ]
        case "Help":
            choices = [("Quick panel help", "help")]
        default:
            choices = QuickPanelRoute.allCases.map { ($0.title, "route:\($0.rawValue)") }
        }
        return choices
    }

    @objc private func performPanelMenu(_ item: NSMenuItem) {
        guard let action = item.representedObject as? String else { return }
        performMenuCommand(action)
    }

    func performMenuCommand(_ action: String) {
        switch action {
        case "workspace", "zoom", "palette", "assistant", "clear", "find", "back", "help":
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
        case "workspace":
            if let section = currentRoute.workspaceSection { open(section) }
        case "zoom": zoomed.toggle()
        case "palette": toggleCommandPalette()
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
        case "volumeDown": performMusic(.volume(-10))
        case "volumeUp": performMusic(.volume(10))
        default: break
        }
    }
}
