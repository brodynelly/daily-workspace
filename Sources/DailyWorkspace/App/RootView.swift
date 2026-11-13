import AppKit
import DailyCore
import SwiftUI

/// The window, in Luuna's shell layout under the native macOS title bar: a collapsible 240 pt sidebar
/// (wordmark, screens, recent notes, the vault status line) beside one column holding the 56 pt top bar
/// and the current screen. Screens own their page column (`Page`), so scrolling stays at the window edge.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var document: NoteDocument
    @EnvironmentObject private var vaultSession: VaultSession
    @EnvironmentObject private var shortcut: GlobalCaptureShortcut
    @Environment(\.openWindow) private var openWindow
    @State private var sidebarVisible = true
    @StateObject private var keyRouter = MainWindowShortcutRouter()

    var body: some View {
        GeometryReader { geometry in
            let splitInspector =
                navigation.showingAssistantPanel && !navigation.showingSettings
                && geometry.size.width >= Metrics.assistantSplitWidth
            let workspaceWidth = max(
                0,
                geometry.size.width - (sidebarVisible ? Metrics.sidebarWidth : 0)
                    - (splitInspector ? Metrics.assistantInspectorWidth + Metrics.borderWidth : 0))
            HStack(spacing: 0) {
                if sidebarVisible { sidebar }
                VStack(spacing: 0) {
                    topBar
                    // Settings replaces the current screen in this column; Back returns to that screen.
                    Group {
                        if navigation.showingSettings { SettingsView() } else { screen }
                    }
                    .id(navigation.showingSettings ? "settings" : navigation.section.rawValue)
                    .viewEntrance()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(width: workspaceWidth)
                .overlay(alignment: .trailing) {
                    if showsOverlayInspector(in: geometry.size.width) {
                        AssistantInspector()
                            .frame(width: min(Metrics.assistantInspectorWidth, workspaceWidth))
                            .overlay(alignment: .leading) { VerticalHairline() }
                    }
                }
                if splitInspector {
                    VerticalHairline()
                    AssistantInspector().frame(width: Metrics.assistantInspectorWidth)
                }
            }
        }
        .background { WorkspaceCanvas() }
        .background {
            MainWindowKeyboardMonitor(handle: handleShortcut)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .foregroundStyle(Theme.inkBody)
        .tint(Theme.accent)
        .toolbar(.hidden, for: .windowToolbar)
        .onAppear {
            shortcut.onCapture = { CommandRunner(model: model, openWindow: openWindow).run(.captureWindow) }
            refreshGlobalCapture()
        }
        .onChange(of: preferences.shortcutOverrides) { _, _ in refreshGlobalCapture() }
        .onChange(of: preferences.isRecordingShortcut) { _, _ in refreshGlobalCapture() }
        .onChange(of: navigation.section) { _, _ in keyRouter.reset() }
        .onChange(of: navigation.showingSettings) { _, _ in keyRouter.reset() }
        .onDisappear { document.saveNow() }
        .sheet(isPresented: $navigation.showCommandPalette) { CommandPaletteView() }
        .sheet(isPresented: $navigation.showQuickCapture) { CaptureForm(style: .sheet) }
    }

    @ViewBuilder private var screen: some View {
        switch navigation.section {
        case .today: TodayView()
        case .projects: ProjectsView()
        case .openLoops: OpenLoopsView()
        case .notes: NotesView()
        case .calendar: CalendarView()
        case .assistant: AssistantView()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            wordmark
            VStack(alignment: .leading, spacing: Space.sHalf) {
                ForEach(AppSection.allCases) { section in
                    NavItem(
                        title: section.title, symbol: section.symbol,
                        current: !navigation.showingSettings && navigation.section == section,
                        shortcut: AppCommand.go(section).configuredLabel(using: preferences)
                    ) { navigation.section = section }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Screens")
            recentNotes
                .frame(maxHeight: .infinity, alignment: .top)
            NavItem(
                title: "Settings", symbol: AppCommand.settings.symbol,
                current: navigation.showingSettings, shortcut: AppCommand.settings.configuredLabel(using: preferences)
            ) { navigation.showSettings() }
            StatusLine(
                tone: vaultSession.state.statusTone, label: vaultSession.state.statusLabel,
                detail: vaultSession.state.statusDetail
            )
            .padding(.horizontal, Space.s2)
            .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s3)
        .padding(.bottom, Space.s4)
        .frame(width: Metrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
        .overlay(alignment: .trailing) { VerticalHairline() }
    }

    private var wordmark: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Daily Workspace")
                .textRole(.wordmark, lineBox: false)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Space.s2)
        .frame(height: Metrics.topBarHeight, alignment: .leading)
    }

    @ViewBuilder private var recentNotes: some View {
        if !preferences.recentNotes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SidebarLabel("Recent notes")
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(preferences.recentNotes, id: \.self) { path in
                            RecentNoteRow(path: path) { model.openNote(path) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recent notes")
        }
    }

    private func showsOverlayInspector(in width: CGFloat) -> Bool {
        navigation.showingAssistantPanel && !navigation.showingSettings && width < Metrics.assistantSplitWidth
    }

    // MARK: Top bar

    private var topBar: some View {
        TopBar {
            Button {
                sidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.quiet)
            .keyboardShortcut(sidebarShortcut)
            .accessibilityLabel(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            .help(shortcutHelp(sidebarVisible ? "Hide Sidebar" : "Show Sidebar", id: "sidebar.toggle"))
            if navigation.showingSettings {
                Button {
                    navigation.closeSettings()
                } label: {
                    Label("Back to \(navigation.section.title)", systemImage: "arrow.left")
                }
                .buttonStyle(.quiet)
                .help("Back to \(navigation.section.title)")
            } else {
                PaletteTrigger(keys: AppCommand.commandPalette.configuredLabel(using: preferences)) {
                    navigation.showCommandPalette = true
                }
            }
            Spacer(minLength: Space.s4)
            if let hint = keyRouter.pendingHint {
                Text(hint).textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
                    .accessibilityLabel("Awaiting the next navigation key")
            }
            if !navigation.showingSettings {
                Button {
                    navigation.showingAssistantPanel.toggle()
                } label: {
                    Label("Ask AI", systemImage: "sparkles")
                }
                .buttonStyle(.quiet)
                .accessibilityLabel(navigation.showingAssistantPanel ? "Hide AI Sidebar" : "Show AI Sidebar")
                .help(shortcutHelp("Toggle AI Sidebar", id: "assistant.panel"))
            }
            Button {
                navigation.showQuickCapture = true
            } label: {
                Label("Capture", systemImage: AppCommand.quickCapture.symbol)
            }
            .buttonStyle(.quiet)
            .help(shortcutHelp("Quick Capture", id: AppCommand.quickCapture.id))
        }
    }
    private var sidebarShortcut: KeyboardShortcut? {
        guard !preferences.isRecordingShortcut else { return nil }
        return KeyboardShortcutCatalog.binding(for: "sidebar.toggle", preferences: preferences)?.menuShortcut
    }

    private func shortcutHelp(_ title: String, id: String) -> String {
        guard let binding = KeyboardShortcutCatalog.binding(for: id, preferences: preferences) else { return title }
        return "\(title) (\(KeyboardShortcutCatalog.label(for: binding)))"
    }

    private func refreshGlobalCapture() {
        shortcut.register(
            binding: preferences.isRecordingShortcut
                ? nil : KeyboardShortcutCatalog.binding(for: "globalCapture", preferences: preferences))
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        if preferences.isRecordingShortcut {
            if let recorder = event.window?.firstResponder as? ShortcutRecordingView {
                recorder.keyDown(with: event)
                return true
            }
            return false
        }
        guard !event.isARepeat, !navigation.showCommandPalette, !navigation.showQuickCapture,
            !(event.window?.firstResponder is NSTextView),
            !(event.window?.firstResponder is NSTextField),
            let stroke = ShortcutStroke(event: event)
        else {
            keyRouter.reset()
            return false
        }
        switch keyRouter.accept(
            stroke, preferences: preferences, activeSection: navigation.showingSettings ? nil : navigation.section,
            assistantPanelVisible: navigation.showingAssistantPanel && !navigation.showingSettings
        ) {
        case .unhandled: return false
        case .waiting: return true
        case .action(let id): return performShortcut(id)
        }
    }
}

extension RootView {

    private func performShortcut(_ id: String) -> Bool {
        switch id {
        case "keyboardHelp":
            navigation.showSettings(tab: .keyboard)
        case "assistant.panel":
            guard !navigation.showingSettings else { return false }
            navigation.showingAssistantPanel.toggle()
        case "quickSearch":
            CommandRunner(model: model, openWindow: openWindow).run(.searchNotes)
        case "sidebar.toggle":
            sidebarVisible.toggle()
        case "calendar.previousWeek", "calendar.nextWeek":
            guard navigation.section == .calendar, !navigation.showingSettings,
                let date = Calendar.current.date(
                    byAdding: .day, value: id == "calendar.previousWeek" ? -7 : 7,
                    to: model.calendar.selectedDay)
            else { return false }
            model.calendar.show(day: date)
        case "assistant.stop":
            guard navigation.section == .assistant || navigation.showingAssistantPanel, !navigation.showingSettings
            else {
                return false
            }
            model.assistant.stop()
        default:
            return runNavigationShortcut(id)
        }
        return true
    }

    private func runNavigationShortcut(_ id: String) -> Bool {
        if id.hasPrefix("goChord."),
            let section = AppSection(rawValue: String(id.dropFirst("goChord.".count)))
        {
            navigation.section = section
            return true
        }
        let command: AppCommand?
        if id == AppCommand.commandPalette.id {
            command = .commandPalette
        } else {
            command = AppCommand.paletteCommands.first(where: { $0.id == id })
        }
        guard let command else { return false }
        let runner = CommandRunner(model: model, openWindow: openWindow)
        guard runner.isEnabled(command) else { return false }
        runner.run(command)
        return true
    }
}

/// A recent note in the sidebar: quiet, muted text with a hover fill.
private struct RecentNoteRow: View {
    let path: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            NoteLabel(path: path)
                .textRole(.bodySmall, lineBox: false)
                .foregroundStyle(hovered ? Theme.ink : Theme.inkMuted)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s1Half)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(hovered ? Theme.fill : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
