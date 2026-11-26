import AppKit
import CoreText
import SwiftUI

/// A panel-only rendering surface. The main Daily Workspace window keeps its own visual system.
@MainActor
struct QuickPanelPascalSkin: View {
    @ObservedObject var controller: QuickPanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState var searchFocused: Bool

    typealias Ink = PascalInk
    typealias Typography = PascalType

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
            let scale = controller.zoomScale(for: controller.zoomKey)
            let width = geometry.size.width / scale
            let height = geometry.size.height / scale
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

                QuickPanelStatsBar(controller: controller, attention: controller.attention)
                    .frame(width: width, height: 29)

                if controller.aiPopup.isVisible {
                    aiPage(width: width, height: height)
                }

                if musicSidebar > 0 && !controller.aiPopup.isVisible {
                    pane("PLAYLISTS", active: controller.focusedPane == "playlists") {
                        playlistList
                    }
                    .frame(width: musicSidebar, height: max(0, height - 78))
                    .offset(x: 7, y: 40)
                }

                if !controller.aiPopup.isVisible {
                    pane(documentTitle, active: controller.focusedPane == "document") {
                        VStack(spacing: 12) {
                            if controller.workspacePath != nil {
                                QuickPanelWorkspacePageView(controller: controller) { documentTable }
                            } else if route == .monitor {
                                QuickPanelMonitorView(controller: controller, monitor: controller.monitor)
                                    .frame(height: max(240, documentHeight * 0.54))
                                    .padding(.top, 8)
                                QuickPanelProcessTable(controller: controller, monitor: controller.monitor)
                            } else {
                                documentTable
                            }
                        }
                    }
                    .frame(width: contentWidth, height: documentHeight)
                    .offset(x: x, y: 40)

                    if showsPreview {
                        pane(previewTitle, active: controller.focusedPane == "preview") {
                            ScrollView { preview }
                        }
                        .frame(width: contentWidth, height: previewHeight)
                        .offset(x: x, y: previewY)
                    }

                    if controller.searchVisible {
                        pane("FIND IN \(route.title.uppercased())", active: controller.focusedPane == "command") {
                            command
                        }
                        .frame(width: contentWidth, height: 84)
                        .offset(x: x, y: commandY)
                    }
                }

                footer
                    .frame(width: width - 24, height: 24, alignment: .leading)
                    .offset(x: 12, y: height - 27)

                if controller.palette.isVisible {
                    QuickPanelCommandPaletteOverlay(controller: controller, palette: controller.palette)
                        .padding(Space.s5)
                        .frame(width: width, height: height)
                        .background(Ink.scrim)
                }
            }
            .frame(width: width, height: height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .font(Typography.font(13, preferred: controller.panelFont))
            .environment(\.quickPanelFont, controller.panelFont)
            .foregroundStyle(Ink.primary)
            .transaction { transaction in
                if reduceMotion { transaction.disablesAnimations = true }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily Workspace Pascal panel, \(route.title)")
        .onChange(of: controller.focusedPane) { _, pane in searchFocused = pane == "command" }
        .onChange(of: controller.searchRequest) { _, _ in searchFocused = true }
    }

    private var documentTitle: String {
        let name =
            controller.shortcutTool ?? controller.workspacePath.map { ($0 as NSString).lastPathComponent }
            ?? (route == .home
                ? "WORKSPACE" : route == .music ? "LIBRARY" : route == .monitor ? "MONITOR" : route.rawValue)
        return "\(name.uppercased()).PAS"
    }

    func pane<Content: View>(
        _ title: String, active: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        PascalPane(title, active: active, content: content)
    }
}
