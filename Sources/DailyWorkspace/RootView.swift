import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var shortcut: GlobalCaptureShortcut
    @State private var navigationQuery = ""
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search workspace", text: $navigationQuery).textFieldStyle(.plain)
            }
            .padding(11).softControlSurface().padding(.horizontal, 12).padding(.top, 14)
            List {
                ForEach(AppState.Section.allCases.filter { navigationQuery.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(navigationQuery) }) { section in
                    Button { state.section = section } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(state.section == section ? Color.white : Color(white: 0.66))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 11)
                            .background(state.section == section ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(state.section == section ? "Selected" : "")
                    .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                if !state.recentNotes.isEmpty {
                    Section("Recent notes") {
                        ForEach(state.recentNotes.filter { navigationQuery.isEmpty || $0.localizedCaseInsensitiveContains(navigationQuery) }, id: \.self) { path in
                            Button {
                                state.openNote(relativePath: path)
                                state.section = .notes
                            } label: {
                                Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                                    .lineLimit(1).font(.system(size: 14)).padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .tint(Color(white: 0.55))
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            }
            .background(Color(red: 0.105, green: 0.103, blue: 0.10))
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
            .safeAreaInset(edge: .bottom) {
                Button {
                    state.showQuickCapture = true
                } label: {
                    Label("Quick Capture", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(10)
                .help("Quick capture (⌘N)")
            }
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
            .transition(.opacity)
        }
        .toolbar {
            ToolbarItem {
                Button { state.showCommandPalette = true } label: { Image(systemName: "command") }
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: state.section)
        .tint(WorkspaceTheme.coral)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.showCommandPalette) { CommandPaletteView() }
        .sheet(isPresented: $state.showQuickCapture) {
            QuickCaptureSheet()
        }
    }
}
