import AppKit
import CoreText
import SwiftUI

/// A panel-only rendering surface. The main Daily Workspace window keeps its own visual system.
@MainActor
struct QuickPanelPascalSkin: View {
    @ObservedObject var controller: QuickPanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState var searchFocused: Bool

    enum Ink {
        static let overlay = Color(red: 9 / 255, green: 35 / 255, blue: 74 / 255).opacity(0.36)
        static let band = Color(red: 66 / 255, green: 98 / 255, blue: 125 / 255).opacity(0.45)
        static let pane = Color(red: 6 / 255, green: 23 / 255, blue: 47 / 255).opacity(0.2)
        static let activeRule = Color(red: 180 / 255, green: 235 / 255, blue: 241 / 255).opacity(0.95)
        static let idleRule = Color(red: 129 / 255, green: 161 / 255, blue: 183 / 255).opacity(0.65)
        static let titleBox = Color(red: 16 / 255, green: 37 / 255, blue: 65 / 255).opacity(0.98)
        static let title = Color(red: 243 / 255, green: 221 / 255, blue: 150 / 255)
        static let inactiveTitle = Color(red: 198 / 255, green: 228 / 255, blue: 237 / 255)
        static let primary = Color(red: 224 / 255, green: 237 / 255, blue: 244 / 255)
        static let footer = Color(red: 216 / 255, green: 234 / 255, blue: 240 / 255)
        static let meta = Color(red: 139 / 255, green: 179 / 255, blue: 198 / 255)
        static let header = Color(red: 10 / 255, green: 36 / 255, blue: 68 / 255).opacity(0.8)
        static let cyan = Color(red: 120 / 255, green: 224 / 255, blue: 230 / 255)
        static let selection = Color(red: 56 / 255, green: 186 / 255, blue: 208 / 255).opacity(0.36)
        static let gold = Color(red: 243 / 255, green: 206 / 255, blue: 131 / 255)
        static let coral = Color(red: 255 / 255, green: 169 / 255, blue: 154 / 255)
        static let notice = Color(red: 244 / 255, green: 205 / 255, blue: 129 / 255)
    }

    enum Typography {
        static func name(_ preferred: String) -> String {
            preferred == "VGA" ? (BundledFonts.vgaName ?? preferred) : preferred
        }

        static func font(_ size: CGFloat, preferred: String) -> Font {
            let selected = name(preferred)
            if NSFont(name: selected, size: size) != nil {
                return .custom(selected, size: size, relativeTo: .body)
            }
            return .system(size: size, design: .monospaced)
        }
    }

    var route: QuickPanelRoute { controller.currentRoute }
    var music: Bool { route == .music }
    var previewTitle: String {
        switch route {
        case .calendar: return "CALENDAR PREVIEW"
        case .agents: return "RUN PREVIEW"
        default: return "TERMINAL PREVIEW"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let musicSidebar = music && !controller.zoomed ? round(width * 0.28) : 0
            let x = musicSidebar > 0 ? musicSidebar + 15 : 7.0
            let contentWidth = max(0, width - x - 7)
            let commandY = height - 122
            let showsPreview = controller.showsPreview
            let bottom = height - 38
            let documentBottom = controller.searchVisible ? bottom - 96 : bottom
            let documentHeight =
                showsPreview
                ? max(100, min(210, (documentBottom - 40) * 0.45))
                : max(100, documentBottom - 40)
            let previewY = 52 + documentHeight
            let previewHeight = showsPreview ? max(80, documentBottom - 64 - documentHeight) : 0

            ZStack(alignment: .topLeading) {
                Ink.overlay
                Ink.band.frame(height: 29)
                Ink.band.frame(height: 28).offset(y: height - 28)

                menuStrip
                    .frame(width: width, height: 29)

                if musicSidebar > 0 {
                    pane("PLAYLISTS", active: controller.focusedPane == "playlists") {
                        playlistList
                    }
                    .frame(width: musicSidebar, height: max(0, height - 78))
                    .offset(x: 7, y: 40)
                }

                pane(documentTitle, active: controller.focusedPane == "document") {
                    documentTable
                }
                .frame(width: contentWidth, height: documentHeight)
                .offset(x: x, y: 40)

                if showsPreview {
                    pane(previewTitle, active: controller.focusedPane == "preview") {
                        preview
                    }
                    .frame(width: contentWidth, height: previewHeight)
                    .offset(x: x, y: previewY)
                }

                if controller.searchVisible {
                    pane(music ? "MUSIC.APP" : "SEARCH / COMMAND", active: controller.focusedPane == "command") {
                        command
                    }
                    .frame(width: contentWidth, height: 84)
                    .offset(x: x, y: commandY)
                }

                footer
                    .frame(width: width - 24, height: 24, alignment: .leading)
                    .offset(x: 12, y: height - 27)

                if controller.palette.isVisible {
                    QuickPanelCommandPaletteOverlay(controller: controller, palette: controller.palette)
                        .frame(width: width, height: height)
                        .background(Color.black.opacity(0.25))
                }
            }
            .frame(width: width, height: height)
            .clipped()
            .font(Typography.font(13, preferred: controller.panelFont))
            .foregroundStyle(Ink.primary)
            .transaction { transaction in
                if reduceMotion { transaction.disablesAnimations = true }
            }
        }
        .accessibilityLabel("Daily Workspace Pascal panel, \(route.title)")
        .onChange(of: controller.focusedPane) { _, pane in searchFocused = pane == "command" }
        .onChange(of: controller.searchRequest) { _, _ in searchFocused = true }
    }

    private var documentTitle: String {
        let name =
            controller.shortcutTool ?? (route == .home ? "WORKSPACE" : route == .music ? "LIBRARY" : route.rawValue)
        return "\(name.uppercased()).PAS"
    }

    private func pane<Content: View>(
        _ title: String, active: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .top) {
            Ink.pane
            content()
                .padding(.horizontal, 9)
                .padding(.top, 18)
                .padding(.bottom, 15)
        }
        .overlay {
            Rectangle().strokeBorder(active ? Ink.activeRule : Ink.idleRule, lineWidth: 1)
                .padding(0.5)
            Rectangle().strokeBorder(active ? Ink.activeRule : Ink.idleRule, lineWidth: 1)
                .padding(3.5)
        }
        .overlay(alignment: .top) {
            Text(" \(title) ")
                .font(Typography.font(13, preferred: controller.panelFont))
                .foregroundStyle(active ? Ink.title : Ink.inactiveTitle)
                .padding(.horizontal, 3)
                .background(Ink.titleBox)
                .offset(y: -7)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var menuStrip: some View {
        HStack(spacing: 4) {
            menu("File") {
                Button("Open \(route.title) in Daily Workspace") {
                    if let section = route.workspaceSection { controller.open(section) }
                }
                .disabled(route.workspaceSection == nil)
                Button("Quick AI Chat") { controller.open(.assistant) }
                    .accessibilityLabel("Quick AI Chat, open shared Assistant")
                Button("Open selection ↵") { controller.activateSelected() }
                Button("Workspace actions ⌘↵") { controller.activateSelected(alternate: true) }
                Button("Refresh ⌘R") { controller.refresh() }
                Button("Close panel") { controller.hide(restoreFocus: true) }
            }
            menu("Edit") {
                Button("Select Home") { controller.navigate(to: .home) }
                Button("Clear search") { controller.query = "" }
                Button("Dismiss / Close session ⌘⌫") { controller.activateSelected(remove: true) }
            }
            if music {
                menu("Play") {
                    Button("Play / Pause F8") { controller.performMusic(.playPause) }
                    Button("Stop") { controller.performMusic(.stop) }
                    Button("Previous F7") { controller.performMusic(.previous) }
                    Button("Next F9") { controller.performMusic(.next) }
                    Button("Volume down F5") { controller.performMusic(.volume(-5)) }
                    Button("Volume up F6") { controller.performMusic(.volume(5)) }
                }
                menu("Shuffle") {
                    Button("Shuffle songs F4") {
                        controller.performMusic(
                            .shuffle(
                                filteredTrackIDs: controller.rows.map {
                                    String($0.id.dropFirst("music:".count))
                                }))
                    }
                    Button("End Shuffle") { controller.performMusic(.endShuffle) }
                }
            } else {
                menu("View") {
                    ForEach(QuickPanelRoute.allCases) { destination in
                        Button(destination.title) { controller.navigate(to: destination) }
                    }
                }
            }
            menu("Window") {
                ForEach(QuickPanelRoute.allCases) { destination in
                    Button(destination.title) { controller.navigate(to: destination) }
                }
            }
            menu("Help") {
                Button("Help F1") { controller.showHelp() }
            }
            Spacer(minLength: 0)
            // While search is hidden, its status line (count, music state, errors) moves here.
            Text(controller.searchVisible ? "DAILY WORKSPACE / PASCAL" : statusLine)
                .font(Typography.font(11, preferred: controller.panelFont))
                .foregroundStyle(controller.searchVisible || statusIsNormal ? Ink.meta : Ink.notice)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
    }

    private func menu<Items: View>(_ name: String, @ViewBuilder items: () -> Items) -> some View {
        QuickPanelMenuIcon(name: name, items: items())
    }

}

/// A menu-strip entry drawn as an SF Symbol; the name stays in its accessibility label and tooltip.
@MainActor
struct QuickPanelMenuIcon<Items: View>: View {
    let name: String
    let items: Items
    @State private var hovered = false

    static func symbol(for name: String) -> String {
        switch name {
        case "File": return "doc.text"
        case "Edit": return "square.and.pencil"
        case "View": return "rectangle.grid.1x2"
        case "Window": return "macwindow.on.rectangle"
        case "Help": return "questionmark.circle"
        case "Play": return "playpause"
        case "Shuffle": return "shuffle"
        default: return "ellipsis.circle"
        }
    }

    var body: some View {
        Menu {
            items
        } label: {
            HStack(spacing: 3) {
                Image(systemName: Self.symbol(for: name))
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 16, height: 16)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .opacity(hovered ? 0.9 : 0.45)
            }
            .foregroundStyle(hovered ? QuickPanelPascalSkin.Ink.gold : QuickPanelPascalSkin.Ink.footer)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(QuickPanelPascalSkin.Ink.selection.opacity(hovered ? 1 : 0))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help("\(name) (⌥\(name.prefix(1)))")
        .accessibilityLabel("\(name) menu")
    }
}
