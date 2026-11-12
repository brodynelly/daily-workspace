import DailyCore
import SwiftUI

/// Today, after Luuna's Home: the date as the title, four counts on a muted tray, then what is due and the agenda
/// beside capture and today's note. Every row keeps its owner's status and source; an unreadable source is said,
/// never shown as "nothing due".
struct TodayView: View {
    var body: some View {
        Page { TodayContent() }
            .navigationTitle(AppSection.today.title)
    }
}

/// The page column's content, apart from `Page` so it can be drawn without a scroll view.
struct TodayContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vaultSession: VaultSession
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var openLoops: OpenLoopsStore
    @State private var noteRevision = 0

    private var hasVault: Bool {
        if case .available = vaultSession.state { return true }
        return false
    }

    var body: some View {
        let day = model.today
        let location = hasVault ? TodayNoteLocation.current(in: model) : nil
        PageHeader(title: Self.title(for: day), description: "Your agenda, what's due, and today's note.") {
            Button {
                model.navigation.showQuickCapture = true
            } label: {
                HStack(spacing: Space.s2) {
                    Text("Quick Capture")
                    Kbd("⌘N")
                }
            }
            .buttonStyle(.workspace(.quiet, size: .large))
            .accessibilityLabel("Quick Capture, Command N")
            Button("Open today's note") { model.openToday(navigate: true) }
                .buttonStyle(.workspace(.secondary, size: .large))
                .disabled(!Self.canOpen(location))
        }
        if !hasVault { VaultConnect(state: vaultSession.state) }
        stats(day: day)
        if hasVault {
            let notices = TodayDue.notices(from: openLoops)
            if !notices.isEmpty {
                Callout(tone: .attention) { ForEach(notices, id: \.self) { Text($0) } }
                    .accessibilityLabel("Some sources could not be read")
            }
        }
        TodayColumns {
            VStack(alignment: .leading, spacing: Space.s6) {
                TodayDueSection(day: day)
                TodayAgendaSection()
            }
            VStack(alignment: .leading, spacing: Space.s5) {
                TodayCaptureSection { noteRevision += 1 }
                if let location { TodayNotePanel(location: location, revision: noteRevision) }
            }
        }
        .task(id: day) { calendar.show(day: Date()) }
    }

    private func stats(day: LocalDay) -> some View {
        let events = calendar.status == .authorized ? TodayAgendaSection.events(of: calendar).count : nil
        return StatGrid(label: "Today summary counts") {
            ForEach(TodayDue.stats(counts: openLoops.counts(on: day), events: events)) {
                StatTile($0.term, value: $0.value, comparison: $0.comparison)
            }
        }
    }

    /// "Thursday, November 12".
    static func title(for day: LocalDay) -> String {
        (day.date() ?? Date()).formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private static func canOpen(_ location: TodayNoteLocation?) -> Bool {
        if case .resolved = location { return true }
        return false
    }
}

/// No usable vault: what is missing, then the one control that adds it.
private struct VaultConnect: View {
    @EnvironmentObject private var model: AppModel
    let state: VaultSession.State

    var body: some View {
        EmptyState(title, description: description, systemImage: "folder", boxed: true) {
            Button(AppCommand.chooseVault.title) { model.chooseVault() }.buttonStyle(.primary)
        }
    }

    private var title: String {
        switch state {
        case .notConfigured, .available: return "No vault selected"
        case .needsReauthorization: return "Vault access needed"
        case .unavailable: return "Vault unavailable"
        }
    }

    private var description: String {
        switch state {
        case .notConfigured, .available:
            return "Choose your Obsidian vault to see Org items due today and today's note. Local tasks and the "
                + "agenda work without it."
        case .needsReauthorization:
            return "macOS no longer lets the app open the vault. Choose the folder again to restore access."
        case .unavailable(let why): return why
        }
    }
}

/// Two columns side by side (3 : 2) when there is room, stacked otherwise. Exactly two subviews; each keeps its
/// identity across the switch, so a capture draft survives a window resize.
private struct TodayColumns: Layout {
    private static let gap = Space.s6
    /// Below this width the columns stack (Luuna stacks its two-column workspaces at 920 pt).
    private static let minimumSideBySide: CGFloat = 840

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat)? {
        guard total >= Self.minimumSideBySide else { return nil }
        let primary = ((total - Self.gap) * 0.58).rounded()
        return (primary, total - Self.gap - primary)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? Self.minimumSideBySide
        if let (left, right) = widths(width) {
            let heights = zip(subviews, [left, right]).map {
                $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height
            }
            return CGSize(width: width, height: heights.max() ?? 0)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + Self.gap * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if let (left, right) = widths(bounds.width) {
            var x = bounds.minX
            for (subview, width) in zip(subviews, [left, right]) {
                subview.place(
                    at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: nil))
                x += width + Self.gap
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(
                at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil))
            y += size.height + Self.gap
        }
    }
}
