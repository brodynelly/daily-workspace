import SwiftUI

/// ⌘K palette over the command registry (Luuna's palette overlay): the search field on the fill at the top,
/// the matching commands grouped into "Go to" and "Actions" with each shortcut as key caps on the right, the
/// selection on the accent ground, and the keys in a hint line. ↑↓ move, ↩ runs, esc closes.
struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var document: NoteDocument
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var runner: CommandRunner {
        CommandRunner(model: model, openWindow: openWindow)
    }

    /// The matching commands in registry order: every screen first, then the actions.
    private var commands: [AppCommand] {
        AppCommand.paletteCommands.filter { command in
            runner.isEnabled(command)
                && (query.isEmpty || command.paletteTitle.localizedCaseInsensitiveContains(query))
        }
    }

    private struct PaletteSection: Identifiable {
        let title: String
        let rows: [(index: Int, command: AppCommand)]
        var id: String { title }
    }

    private var groups: [PaletteSection] {
        let indexed = Array(commands.enumerated()).map { (index: $0.offset, command: $0.element) }
        let screens = indexed.filter { if case .go = $0.command { return true } else { return false } }
        let actions = indexed.filter { if case .go = $0.command { return false } else { return true } }
        return [PaletteSection(title: "Go to", rows: screens), PaletteSection(title: "Actions", rows: actions)]
            .filter { !$0.rows.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Hairline()
            results
            Hairline()
            hint
        }
        .frame(width: Self.width, height: 460)
        .background(Theme.surfaceOverlay)
        .presentationBackground(Theme.surfaceOverlay)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onExitCommand { dismiss() }
    }

    /// `--palette-width`.
    private static let width: CGFloat = 600

    private var searchField: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .iconRole(.inline)
                .foregroundStyle(Theme.inkMuted)
                .accessibilityHidden(true)
            TextField(
                "Search commands", text: $query,
                prompt: Text("Type a command or screen…").foregroundStyle(Theme.inkMuted)
            )
            .textFieldStyle(.plain)
            .font(TextRole.body.font)
            .foregroundStyle(Theme.ink)
            .focused($searchFocused)
            .onSubmit(runSelection)
            .onKeyPress(.downArrow) {
                move(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                move(by: -1)
                return .handled
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
        }
        .padding(.horizontal, Space.s3)
        .frame(height: Metrics.controlLg)
        .surface(Theme.fill)
        .padding(Space.s3)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(groups) { group in
                        Text(group.title)
                            .textRole(.overline, lineBox: false)
                            .foregroundStyle(Theme.inkMuted)
                            .padding(EdgeInsets(top: Space.s2, leading: Space.s2Half, bottom: 0, trailing: 0))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.rows, id: \.command.id) { row in
                            PaletteRow(command: row.command, selected: selection == row.index) {
                                execute(row.command)
                            }
                            .id(row.index)
                            .onHover { if $0 { selection = row.index } }
                        }
                    }
                    if commands.isEmpty {
                        Text("No matching commands")
                            .textRole(.label, lineBox: false)
                            .foregroundStyle(Theme.inkMuted)
                            .padding(Space.s4)
                    }
                }
                .padding(Space.s1)
            }
            .onChange(of: selection) { _, value in proxy.scrollTo(value) }
        }
    }

    private var hint: some View {
        HStack(spacing: Space.s4) {
            keyHint(["↑", "↓"], "to move")
            keyHint(["↩"], "to run")
            keyHint(["esc"], "to close")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
    }

    private func keyHint(_ keys: [String], _ action: String) -> some View {
        HStack(spacing: Space.s1) {
            ForEach(keys, id: \.self) { Kbd($0) }
            Text(action).textRole(.caption, lineBox: false).foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private func move(by step: Int) {
        guard !commands.isEmpty else { return }
        selection = min(max(0, selection + step), commands.count - 1)
    }

    private func runSelection() {
        if commands.indices.contains(selection) { execute(commands[selection]) }
    }

    private func execute(_ command: AppCommand) {
        let runner = runner
        dismiss()
        // Let the palette finish dismissing before another sheet or panel opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { runner.run(command) }
    }
}

/// One command: its symbol, its title, and its shortcut as key caps on the right. Selected (by the keys or
/// the pointer) it sits on the accent's soft ground in full ink; nothing else moves.
private struct PaletteRow: View {
    @EnvironmentObject private var preferences: Preferences
    let command: AppCommand
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: command.symbol)
                    .iconRole(.inline)
                    .foregroundStyle(selected ? Theme.accentText : Theme.inkMuted)
                    .frame(width: Metrics.iconSize)
                    .accessibilityHidden(true)
                Text(rowTitle)
                    .textRole(.label, lineBox: false)
                    .fontWeight(.regular)
                    .foregroundStyle(selected ? Theme.ink : Theme.inkBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !command.configuredLabel(using: preferences).isEmpty {
                    Kbd(command.configuredLabel(using: preferences))
                }
            }
            .padding(.horizontal, Space.s2Half)
            .padding(.vertical, Space.s1Half)
            .frame(minHeight: Metrics.controlMd)
            .surface(selected ? Theme.accentSoft : .clear)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(command.paletteTitle)
        .accessibilityValue(command.configuredLabel(using: preferences))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Under the "Go to" heading a screen reads by its name alone.
    private var rowTitle: String {
        if case .go(let section) = command { return section.title }
        return command.title
    }
}
