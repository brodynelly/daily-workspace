import SwiftUI

/// ⌘K palette over the command registry.
struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var document: NoteDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var runner: CommandRunner {
        CommandRunner(model: model, openWindow: openWindow, openSettings: { openSettings() })
    }

    private var commands: [AppCommand] {
        AppCommand.paletteCommands.filter { command in
            runner.isEnabled(command)
                && (query.isEmpty || command.paletteTitle.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type a command or screen…", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { if commands.indices.contains(selection) { execute(commands[selection]) } }
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction)
            }
            .font(.title3).padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                            row(command, selected: selection == index)
                                .id(index)
                                .onHover { if $0 { selection = index } }
                        }
                        if commands.isEmpty { Text("No matching commands").foregroundStyle(.secondary).padding(32) }
                    }
                    .padding(8)
                }
                .onChange(of: selection) { _, value in proxy.scrollTo(value) }
            }
            Divider()
            HStack {
                Text("↑↓ Navigate")
                Spacer()
                Text("↩ Run")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: 520, height: 440)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onMoveCommand { direction in
            if direction == .down { selection = min(selection + 1, max(0, commands.count - 1)) }
            if direction == .up { selection = max(0, selection - 1) }
        }
    }

    private func row(_ command: AppCommand, selected: Bool) -> some View {
        Button {
            execute(command)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: command.symbol).frame(width: 20)
                Text(command.paletteTitle)
                Spacer()
                Text(command.shortcutLabel).font(.body.monospacedDigit()).foregroundStyle(.secondary)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                selected ? WorkspaceTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func execute(_ command: AppCommand) {
        let runner = runner
        dismiss()
        // Let the palette finish dismissing before another sheet or panel opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { runner.run(command) }
    }
}
