import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var shortcut: GlobalCaptureShortcut
    @State private var navigationQuery = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { state.section }, set: { if let s = $0 { state.section = s } })) {
                Section {
                    ForEach(AppState.Section.allCases.filter { navigationQuery.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(navigationQuery) }) { section in
                        Label(section.rawValue, systemImage: section.symbol).tag(section)
                    }
                }
                let recents = state.recentNotes.filter { navigationQuery.isEmpty || $0.localizedCaseInsensitiveContains(navigationQuery) }
                if !recents.isEmpty {
                    Section("Recent Notes") {
                        ForEach(recents, id: \.self) { path in
                            Button {
                                state.openNote(relativePath: path)
                                state.section = .notes
                            } label: {
                                Label(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, systemImage: "doc")
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $navigationQuery, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            Group {
                switch state.section {
                case .today: TodayView()
                case .notes: NotesView()
                case .tasks: TasksView()
                case .calendar: CalendarView()
                case .search: NoteBrowserView()
                case .reminders: RemindersView()
                case .chat: ChatView(chat: state.chatService)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { WorkspaceCanvas() }
            .id(state.section)
        }
        .toolbar {
            ToolbarItem {
                Button { state.showCommandPalette = true } label: { Label("Search Actions", systemImage: "command") }
                    .help("Search actions (⌘K)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { state.showQuickCapture = true } label: {
                    Label("Quick Capture", systemImage: "square.and.pencil")
                }
                .help("Quick Capture (⌘N)")
            }
        }
        .onAppear {
            shortcut.onCapture = {
                openWindow(id: "capture")
                NSApp.activate(ignoringOtherApps: true)
            }
            shortcut.register()
        }
        .onDisappear { state.saveNow() }
        .sheet(isPresented: $state.showCommandPalette) { CommandPaletteView() }
        .sheet(isPresented: $state.showQuickCapture) {
            QuickCaptureSheet()
        }
    }
}
