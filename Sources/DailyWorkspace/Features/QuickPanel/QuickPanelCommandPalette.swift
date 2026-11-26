import AppKit
import DailyCore
import SwiftUI

/// One command in the panel's popup. Every action stays inside the quick panel
/// unless its title says it opens Daily Workspace.
struct QuickPanelPaletteItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var keys = ""
    var group = "Actions"
    let perform: @MainActor () -> Void
}

/// State for the popup drawn over the quick panel: ⌘K shows every command, `m` and ⌥ menus show one menu.
/// It never opens the main window by itself.
@MainActor
final class QuickPanelCommandPalette: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var title = "COMMAND"
    @Published var query = "" { didSet { selectedIndex = 0 } }
    @Published var selectedIndex = 0
    /// A menu's own items; `nil` means the full command list.
    private(set) var scopedItems: [QuickPanelPaletteItem]?

    func open(title: String = "COMMAND", items: [QuickPanelPaletteItem]? = nil) {
        self.title = title
        scopedItems = items
        query = ""
        selectedIndex = 0
        isVisible = true
    }

    func close() {
        guard isVisible else { return }
        isVisible = false
        scopedItems = nil
        query = ""
    }

    func filter(_ items: [QuickPanelPaletteItem]) -> [QuickPanelPaletteItem] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let haystack = "\(item.title) \(item.keys) \(item.group)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

extension QuickPanelController {
    var paletteItems: [QuickPanelPaletteItem] {
        var items = QuickPanelRoute.allCases.map { route in
            QuickPanelPaletteItem(
                id: "route:\(route.rawValue)", title: route.title, symbol: route.symbol,
                keys: Self.vimNumberRoutes.first { $0.value == route }.map { String($0.key) } ?? "", group: "Go to"
            ) { [weak self] in self?.navigate(to: route) }
        }
        items += [
            .init(id: "open", title: "Open selection", symbol: "arrow.turn.down.left", keys: "l") { [weak self] in
                self?.activateSelected()
            },
            .init(
                id: "alternate", title: "Workspace actions", symbol: "ellipsis.rectangle", keys: "a"
            ) { [weak self] in
                self?.activateSelected(alternate: true)
            },
            .init(id: "find", title: "Find in panel", symbol: "magnifyingglass", keys: "/") { [weak self] in
                self?.focusSearch()
            },
            .init(id: "ai", title: "Ask AI", symbol: "sparkles", keys: "?") { [weak self] in
                self?.toggleAssistantPane()
            },
            .init(id: "refresh", title: "Refresh", symbol: "arrow.clockwise", keys: "r") { [weak self] in
                self?.refresh()
            },
            .init(
                id: "zoom", title: zoomed ? "Unzoom" : "Zoom", symbol: "arrow.up.left.and.arrow.down.right", keys: "z"
            ) { [weak self] in
                self?.zoomed.toggle()
            },
            .init(id: "help", title: "Help", symbol: "questionmark.circle") { [weak self] in
                self?.showHelp()
            },
            .init(id: "close", title: "Close panel", symbol: "xmark.circle", keys: "q") { [weak self] in
                self?.hide(restoreFocus: true)
            },
        ]
        if let section = currentRoute.workspaceSection {
            items.append(
                .init(
                    id: "workspace", title: "Open \(section.title) in Daily Workspace", symbol: "macwindow",
                    group: "Daily Workspace"
                ) { [weak self] in self?.open(section) })
        }
        items.append(
            .init(
                id: "assistant", title: "Open Assistant in Daily Workspace",
                symbol: "bubble.left.and.text.bubble.right",
                group: "Daily Workspace"
            ) { [weak self] in self?.open(.assistant) })
        return items
    }

    /// The popup's current list: one menu's items, or every command.
    var visiblePaletteItems: [QuickPanelPaletteItem] { palette.filter(palette.scopedItems ?? paletteItems) }

    func toggleCommandPalette() {
        if palette.isVisible { palette.close() } else { palette.open() }
        objectWillChange.send()
    }

    /// Shows one of the panel's menus (`m` for all of them, ⌥F/E/… for one) in the ⌘K popup's style.
    func openMenuPopup(_ name: String) {
        let menu = panelMenu(named: name)
        var items: [QuickPanelPaletteItem] = []
        for entry in menu.items {
            if let submenu = entry.submenu {
                items += submenu.items.map { menuPaletteItem($0, group: entry.title) }
            } else {
                items.append(menuPaletteItem(entry, group: name))
            }
        }
        palette.open(title: name == "Context" ? "MENU" : name.uppercased(), items: items)
        objectWillChange.send()
    }

    private func menuPaletteItem(_ item: NSMenuItem, group: String) -> QuickPanelPaletteItem {
        let command = item.representedObject as? String ?? item.title
        let route = command.hasPrefix("route:") ? QuickPanelRoute(rawValue: String(command.dropFirst(6))) : nil
        return QuickPanelPaletteItem(
            id: "\(group):\(command)", title: item.title, symbol: route?.symbol ?? Self.menuSymbol(command),
            group: group
        ) {
            if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        }
    }

    private static let menuSymbols: [String: String] = [
        "open": "arrow.turn.down.left", "alternate": "ellipsis.rectangle", "assistant": "sparkles",
        "workspace": "macwindow", "remove": "xmark.bin", "refresh": "arrow.clockwise", "close": "xmark.circle",
        "find": "magnifyingglass", "clear": "delete.left", "back": "chevron.left", "help": "questionmark.circle",
        "playpause": "playpause", "stop": "stop", "previous": "backward", "next": "forward",
        "shuffle": "shuffle", "endShuffle": "shuffle", "volumeDown": "speaker.wave.1", "volumeUp": "speaker.wave.3",
    ]

    private static func menuSymbol(_ command: String) -> String { menuSymbols[command] ?? "circle.dashed" }

    var commandPaletteBinding: ShortcutBinding? {
        let id = AppCommand.commandPalette.id
        if let model { return KeyboardShortcutCatalog.binding(for: id, preferences: model.preferences) }
        return KeyboardShortcutCatalog.definitions.first { $0.id == id }?.defaultBinding
    }

    /// While the popup is open it owns the keyboard; ⌘-shortcuts other than ⌘K fall through to the menu bar.
    func handlePaletteKey(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let matches = visiblePaletteItems
        switch keyCode {
        case 53: toggleCommandPalette()
        case 125, 48: movePaletteSelection(by: 1, count: matches.count)
        case 126: movePaletteSelection(by: -1, count: matches.count)
        case 36, 76:
            guard matches.indices.contains(palette.selectedIndex) else { return true }
            let item = matches[palette.selectedIndex]
            toggleCommandPalette()
            item.perform()
        case 51, 117:
            if !palette.query.isEmpty { palette.query.removeLast() }
        default:
            if modifiers.contains(.command) || modifiers.contains(.control) { return false }
            if characters.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) {
                palette.query += characters
            }
        }
        return true
    }

    private func movePaletteSelection(by offset: Int, count: Int) {
        guard count > 0 else { return }
        palette.selectedIndex = (palette.selectedIndex + offset + count) % count
    }
}

/// The popup, laid out like Daily Workspace's ⌘K palette in the panel's Pascal colours.
@MainActor
struct QuickPanelCommandPaletteOverlay: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var palette: QuickPanelCommandPalette
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        let items = controller.visiblePaletteItems
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.meta)
                Text(palette.query.isEmpty ? "Type a command or panel…" : palette.query)
                    .foregroundStyle(palette.query.isEmpty ? Ink.meta : Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
            }
            .font(.system(size: 14))
            .padding(.horizontal, 18)
            .frame(height: 50)
            Rectangle().fill(Ink.idleRule.opacity(0.45)).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index == 0 || items[index - 1].group != item.group {
                                Text(item.group)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Ink.cyan)
                                    .padding(.horizontal, 10)
                                    .padding(.top, index == 0 ? 2 : 12)
                                    .padding(.bottom, 4)
                            }
                            row(item, selected: index == palette.selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    controller.toggleCommandPalette()
                                    item.perform()
                                }
                        }
                        if items.isEmpty {
                            Text("No matching command").foregroundStyle(Ink.meta)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
                .onChange(of: palette.selectedIndex) { _, index in
                    if items.indices.contains(index) { proxy.scrollTo(items[index].id) }
                }
            }
            Rectangle().fill(Ink.idleRule.opacity(0.45)).frame(height: 1)
            HStack(spacing: 16) {
                QuickPanelKeyCaps(keys: "↑ ↓", label: "to move")
                QuickPanelKeyCaps(keys: "↵", label: "to run")
                QuickPanelKeyCaps(keys: "esc", label: "to close")
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 16)
            .frame(height: 36)
        }
        .frame(maxWidth: 620, maxHeight: 480)
        .background(Ink.titleBox)
        .overlay {
            Rectangle().strokeBorder(Ink.activeRule, lineWidth: 1).padding(0.5)
            Rectangle().strokeBorder(Ink.activeRule, lineWidth: 1).padding(3.5)
        }
        .overlay(alignment: .top) {
            Text(" \(palette.title) ")
                .foregroundStyle(Ink.title)
                .background(Ink.titleBox)
                .offset(y: -8)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick panel commands")
    }

    private func row(_ item: QuickPanelPaletteItem, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 13))
                .frame(width: 20)
                .foregroundStyle(selected ? Ink.gold : Ink.cyan)
            Text(item.title).lineLimit(1)
                .foregroundStyle(selected ? Ink.primary : Ink.footer)
            Spacer(minLength: 16)
            if !item.keys.isEmpty { QuickPanelKeyCaps(keys: item.keys) }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(selected ? Ink.selection : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
