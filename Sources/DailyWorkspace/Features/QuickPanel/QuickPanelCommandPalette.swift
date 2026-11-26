import AppKit
import DailyCore
import SwiftUI

/// One command in the panel's own ⌘K palette. Every action stays inside the quick panel
/// unless its title says it opens Daily Workspace.
struct QuickPanelPaletteItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var keys = ""
    let perform: @MainActor () -> Void
}

/// State for the ⌘K popup drawn over the quick panel. It never opens the main window by itself.
@MainActor
final class QuickPanelCommandPalette: ObservableObject {
    @Published private(set) var isVisible = false
    @Published var query = "" { didSet { selectedIndex = 0 } }
    @Published var selectedIndex = 0

    func open() {
        query = ""
        selectedIndex = 0
        isVisible = true
    }

    func close() {
        guard isVisible else { return }
        isVisible = false
        query = ""
    }

    func filter(_ items: [QuickPanelPaletteItem]) -> [QuickPanelPaletteItem] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let haystack = "\(item.title) \(item.keys)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

extension QuickPanelController {
    var paletteItems: [QuickPanelPaletteItem] {
        var items = QuickPanelRoute.allCases.map { route in
            QuickPanelPaletteItem(
                id: "route:\(route.rawValue)", title: "Go to \(route.title)", symbol: route.symbol,
                keys: Self.vimNumberRoutes.first { $0.value == route }.map { String($0.key) } ?? ""
            ) { [weak self] in self?.navigate(to: route) }
        }
        items += [
            .init(id: "find", title: "Find in panel", symbol: "magnifyingglass", keys: "/") { [weak self] in
                self?.focusSearch()
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
            .init(id: "assistant", title: "Quick AI Chat (opens Daily Workspace)", symbol: "sparkles") { [weak self] in
                self?.open(.assistant)
            },
        ]
        if let section = currentRoute.workspaceSection {
            items.append(
                .init(
                    id: "workspace", title: "Open \(section.title) in Daily Workspace", symbol: "macwindow"
                ) { [weak self] in self?.open(section) })
        }
        items.append(
            .init(id: "close", title: "Close panel", symbol: "xmark.circle", keys: "q") { [weak self] in
                self?.hide(restoreFocus: true)
            })
        return items
    }

    func toggleCommandPalette() {
        if palette.isVisible { palette.close() } else { palette.open() }
        objectWillChange.send()
    }

    /// While the popup is open it owns the keyboard; ⌘-shortcuts other than ⌘K fall through to the menu bar.
    func handlePaletteKey(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let matches = palette.filter(paletteItems)
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

/// The ⌘K popup, drawn in the panel's Pascal style.
@MainActor
struct QuickPanelCommandPaletteOverlay: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var palette: QuickPanelCommandPalette
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        let items = palette.filter(controller.paletteItems)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.gold)
                Text(palette.query.isEmpty ? "Type a command…" : palette.query)
                    .foregroundStyle(palette.query.isEmpty ? Ink.meta : Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Button {
                    controller.toggleCommandPalette()
                } label: {
                    keyCap("esc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close command palette")
            }
            .padding(.horizontal, 18)
            .frame(height: 46)
            Rectangle().fill(Ink.idleRule.opacity(0.6)).frame(height: 1).padding(.horizontal, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, selected: index == palette.selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    controller.toggleCommandPalette()
                                    item.perform()
                                }
                        }
                        if items.isEmpty {
                            Text("No matching command").foregroundStyle(Ink.meta)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .onChange(of: palette.selectedIndex) { _, index in
                    if items.indices.contains(index) { proxy.scrollTo(items[index].id) }
                }
            }
            Rectangle().fill(Ink.idleRule.opacity(0.6)).frame(height: 1).padding(.horizontal, 10)
            HStack(spacing: 16) {
                hint("↑↓", "Move")
                hint("↵", "Run")
                hint("Esc", "Close")
                Spacer(minLength: 0)
                Text("\(items.count) commands").foregroundStyle(Ink.meta)
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 18)
            .frame(height: 32)
        }
        .frame(maxWidth: 600, maxHeight: 470)
        .background(Ink.titleBox)
        .overlay {
            Rectangle().strokeBorder(Ink.activeRule, lineWidth: 1).padding(0.5)
            Rectangle().strokeBorder(Ink.activeRule, lineWidth: 1).padding(3.5)
        }
        .overlay(alignment: .top) {
            Text(" COMMAND ")
                .foregroundStyle(Ink.title)
                .background(Ink.titleBox)
                .offset(y: -8)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick panel commands")
    }

    private func row(_ item: QuickPanelPaletteItem, selected: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 13))
                .frame(width: 20)
                .foregroundStyle(selected ? Ink.gold : Ink.cyan)
            Text(item.title).lineLimit(1)
                .foregroundStyle(selected ? Ink.primary : Ink.footer)
            Spacer(minLength: 16)
            if !item.keys.isEmpty { keyCap(item.keys) }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(selected ? Ink.selection : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Ink.gold)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Ink.idleRule.opacity(0.7), lineWidth: 1)
            )
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).foregroundStyle(Ink.gold)
            Text(label).foregroundStyle(Ink.meta)
        }
    }
}
