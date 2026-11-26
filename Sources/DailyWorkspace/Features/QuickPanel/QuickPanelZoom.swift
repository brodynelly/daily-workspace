import Foundation

/// ⌘+ / ⌘- / ⌘0 zoom the view you are on. Each panel view (and the AI chat popup) keeps its own level in
/// Settings, so Monitor can stay large while Home stays compact.
extension QuickPanelController {
    static let zoomLevels: [Double] = [0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.4, 1.6]

    var zoomKey: String { aiPopup.isVisible ? "ai-chat" : currentRoute.rawValue }

    func zoomScale(for key: String) -> Double {
        let value = model?.preferences.quickPanelZoom[key] ?? 1
        return Self.zoomLevels.contains(value) ? value : 1
    }

    var zoomScale: Double { zoomScale(for: currentRoute.rawValue) }
    var aiZoomScale: Double { zoomScale(for: "ai-chat") }

    func zoom(by steps: Int) {
        let levels = Self.zoomLevels
        let current = levels.firstIndex(of: zoomScale(for: zoomKey)) ?? levels.firstIndex(of: 1) ?? 0
        setZoom(levels[min(levels.count - 1, max(0, current + steps))])
    }

    func resetZoom() { setZoom(1) }

    private func setZoom(_ value: Double) {
        guard let preferences = model?.preferences else { return }
        if value == 1 {
            preferences.quickPanelZoom.removeValue(forKey: zoomKey)
        } else {
            preferences.quickPanelZoom[zoomKey] = value
        }
        objectWillChange.send()
    }

    /// ⌘= / ⌘+ / ⌘- / ⌘0 outside the AI popup.
    func handleZoomKey(_ key: String, command: Bool) -> Bool {
        guard command else { return false }
        switch key {
        case "=", "+": zoom(by: 1)
        case "-": zoom(by: -1)
        case "0": resetZoom()
        default: return false
        }
        return true
    }
}
