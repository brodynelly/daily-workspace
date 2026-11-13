import AppKit

final class QuickPanelWindow: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

struct QuickPanelNavigationEntry {
    let route: QuickPanelRoute
    let shortcutTool: String?
    let workspacePath: String?
}

extension QuickPanelController {
    func positionPanelOnScreen() {
        let mouse = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? NSScreen.screens.first
        if let area = screen?.visibleFrame {
            let width = min(1060, max(1, area.width - 36))
            let height = min(680, max(1, area.height - 36))
            var frame = NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
            if currentRoute == .system {
                frame.origin.x = max(area.minX + 12, min(mouse.x - 40, area.maxX - width - 12))
                frame.origin.y = area.maxY - height - 10
            }
            panel.setFrame(frame, display: false)
        }
    }
}
