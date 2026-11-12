import SwiftUI

/// The window, in Luuna's shell layout under the native macOS title bar: a flat 240 pt sidebar (wordmark,
/// screens, recent notes, the vault status line) beside one column holding the 56 pt top bar and the
/// current screen. Screens own their page column (`Page`), so scrolling stays at the window edge.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var document: NoteDocument
    @EnvironmentObject private var vaultSession: VaultSession
    @EnvironmentObject private var shortcut: GlobalCaptureShortcut
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                topBar
                // A new identity per screen: the old screen leaves at once and the new one fades in, so
                // nothing shows behind it. Instant under Reduce Motion.
                screen
                    .id(navigation.section)
                    .viewEntrance()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background { WorkspaceCanvas() }
        .foregroundStyle(Theme.inkBody)
        .tint(Theme.accent)
        .toolbar(.hidden, for: .windowToolbar)
        .onAppear {
            shortcut.onCapture = { CommandRunner(model: model, openWindow: openWindow).run(.captureWindow) }
            shortcut.register()
        }
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
                        title: section.title, symbol: section.symbol, current: navigation.section == section,
                        shortcut: AppCommand.go(section).shortcutLabel
                    ) { navigation.section = section }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Screens")
            recentNotes
                .frame(maxHeight: .infinity, alignment: .top)
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

    // MARK: Top bar

    private var topBar: some View {
        TopBar {
            PaletteTrigger(keys: AppCommand.commandPalette.shortcutLabel) {
                navigation.showCommandPalette = true
            }
            Spacer(minLength: Space.s4)
            Button {
                navigation.showQuickCapture = true
            } label: {
                Label("Capture", systemImage: AppCommand.quickCapture.symbol)
            }
            .buttonStyle(.quiet)
            .help("Quick Capture (\(AppCommand.quickCapture.shortcutLabel))")
        }
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
