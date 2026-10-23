import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private struct Action: Identifiable {
        let id: String
        let symbol: String
        let shortcut: String
        let run: () -> Void
    }

    private var actions: [Action] {
        [
            Action(id: "Quick Capture", symbol: "plus", shortcut: "⌘ N") { state.showQuickCapture = true },
            Action(id: "Open Today's Note", symbol: "doc.text", shortcut: "⇧ ⌘ T") { state.section = .notes; state.openToday() },
            Action(id: "Browse Notes", symbol: "rectangle.on.rectangle", shortcut: "⌘ 5") { state.section = .search },
            Action(id: "AI Chat", symbol: "bubble.left.and.bubble.right", shortcut: "⌘ 7") { state.section = .chat },
            Action(id: "Today's Tasks", symbol: "checklist", shortcut: "⌘ 3") { state.section = .tasks },
            Action(id: "Calendar", symbol: "calendar", shortcut: "⌘ 4") { state.section = .calendar },
            Action(id: "Reminders", symbol: "list.bullet.circle", shortcut: "⌘ 6") { state.section = .reminders },
            Action(id: "Choose Vault…", symbol: "folder.badge.plus", shortcut: "") { state.chooseVault() },
            Action(id: "Settings", symbol: "slider.horizontal.3", shortcut: "⌘ ,") { openSettings() }
        ].filter { query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search for actions…", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { if actions.indices.contains(selection) { execute(actions[selection]) } }
                Button { dismiss() } label: { Text("esc").font(.caption).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            .font(.system(size: 19)).padding(22)
            Divider().opacity(0.5)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            Button { execute(action) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: action.symbol).frame(width: 24)
                                    Text(action.id)
                                    Spacer()
                                    Text(action.shortcut).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(action.shortcut.isEmpty ? 0 : 0.15)))
                                }
                                .font(.system(size: 17, weight: .medium))
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .background(selection == index ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 13))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).id(index)
                            .onHover { if $0 { selection = index } }
                        }
                        if actions.isEmpty { Text("No matching actions").foregroundStyle(.secondary).padding(32) }
                    }.padding(10)
                }
                .onChange(of: selection) { _, value in proxy.scrollTo(value) }
            }
            Divider().opacity(0.4)
            HStack {
                Text("↑ ↓ to navigate"); Spacer(); Text("↩ to select")
            }.font(.caption).foregroundStyle(.secondary).padding(14)
        }
        .frame(width: 520, height: 570)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onMoveCommand { direction in
            if direction == .down { selection = min(selection + 1, max(0, actions.count - 1)) }
            if direction == .up { selection = max(0, selection - 1) }
        }
    }

    private func execute(_ action: Action) {
        dismiss()
        // Let the palette finish dismissing before another sheet or file panel opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { action.run() }
    }
}
