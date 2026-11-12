import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var document: NoteDocument
    @EnvironmentObject private var shortcut: GlobalCaptureShortcut
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { navigation.section }, set: { if let s = $0 { navigation.section = s } })) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.symbol).tag(section)
                    }
                }
                if !preferences.recentNotes.isEmpty {
                    Section("Recent Notes") {
                        ForEach(preferences.recentNotes, id: \.self) { path in
                            Button {
                                model.openNote(path)
                            } label: {
                                NoteLabel(path: path, icon: "doc")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            Group {
                switch navigation.section {
                case .today: TodayView()
                case .notes: NotesView()
                case .tasks: TasksView()
                case .calendar: CalendarView()
                case .search: SearchView()
                case .reminders: RemindersView()
                case .chat: ChatView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { WorkspaceCanvas() }
            .id(navigation.section)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    navigation.showCommandPalette = true
                } label: {
                    Label(AppCommand.commandPalette.title, systemImage: AppCommand.commandPalette.symbol)
                }
                .help("Command Palette (\(AppCommand.commandPalette.shortcutLabel))")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.showQuickCapture = true
                } label: {
                    Label(AppCommand.quickCapture.title, systemImage: AppCommand.quickCapture.symbol)
                }
                .help("Quick Capture (\(AppCommand.quickCapture.shortcutLabel))")
            }
        }
        .onAppear {
            shortcut.onCapture = { CommandRunner(model: model, openWindow: openWindow).run(.captureWindow) }
            shortcut.register()
        }
        .onDisappear { document.saveNow() }
        .sheet(isPresented: $navigation.showCommandPalette) { CommandPaletteView() }
        .sheet(isPresented: $navigation.showQuickCapture) { CaptureForm(style: .sheet) }
    }
}
