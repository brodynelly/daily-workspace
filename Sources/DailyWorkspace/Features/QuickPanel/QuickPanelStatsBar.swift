import SwiftUI

/// The panel's top band: live counts from the panel's own sources instead of a menu ribbon.
/// Every command lives in the ⌘K popup, `m` and the ⌥ menus.
@MainActor
struct QuickPanelStatsBar: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var attention: QuickPanelAttention
    private typealias Ink = QuickPanelPascalSkin.Ink

    private var route: QuickPanelRoute { controller.currentRoute }

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 7) {
                Image(systemName: controller.aiPopup.isVisible ? "sparkles" : route.symbol).foregroundStyle(Ink.cyan)
                Text(controller.aiPopup.isVisible ? "AI CHAT" : route.title.uppercased()).foregroundStyle(Ink.title)
            }
            if let error = controller.error {
                Text(error).foregroundStyle(Ink.notice)
            } else {
                stat("\(controller.rows.count)", controller.rows.count == 1 ? "item" : "items")
            }
            if !attention.rows.isEmpty {
                HStack(spacing: 5) {
                    Circle().fill(Ink.coral).frame(width: 6, height: 6)
                    Text("\(attention.rows.count) need attention").foregroundStyle(Ink.coral)
                }
            }
            if let track = controller.music.status?.track, !track.name.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "music.note").foregroundStyle(Ink.cyan)
                    Text("\(track.name) — \(track.artist)").foregroundStyle(Ink.footer)
                }
            }
            if controller.model?.assistant.isStreaming == true {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").foregroundStyle(Ink.gold)
                    Text("AI answering").foregroundStyle(Ink.footer)
                }
            }
            Spacer(minLength: 8)
            QuickPanelKeyCaps(keys: "⌘K", label: "Commands")
            TimelineView(.everyMinute) { context in
                Text(context.date.formatted(date: .omitted, time: .shortened)).foregroundStyle(Ink.meta)
            }
        }
        .font(QuickPanelPascalSkin.Typography.font(11, preferred: controller.panelFont))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Panel status")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).foregroundStyle(Ink.primary)
            Text(label).foregroundStyle(Ink.meta)
        }
    }
}
