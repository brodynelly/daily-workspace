import AppKit
import DailyCore
import SwiftUI

/// Searchable shortcut reference and focused key-event recorder, embedded in the workspace Settings tab.
struct KeyboardShortcutsSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var query = ""
    @State private var capturingID: String?
    @State private var firstStroke: ShortcutStroke?
    @State private var message: String?

    private let groups = ["Navigation", "Actions", "Calendar", "Assistant", "Global", "Quick Panel"]

    var body: some View {
        SettingsPage {
            HStack {
                TextField("Search shortcuts", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search keyboard shortcuts")
                Button("Reset All", action: resetAll)
                    .disabled(preferences.shortcutOverrides.isEmpty)
                    .accessibilityLabel("Reset all keyboard shortcuts to defaults")
            }
            SettingsNote(
                "Click Rebind, then press a key. Press a second key for a sequence, or Save one key. "
                    + "Escape cancels. Single-letter shortcuts work only outside text editing.")
            if let message {
                Text(message).foregroundStyle(Theme.inkBody)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            ForEach(groups, id: \.self) { group in
                let rows = KeyboardShortcutCatalog.definitions.filter {
                    $0.group == group
                        && (query.isEmpty
                            || "\($0.title) \($0.group) \($0.id) \(KeyboardShortcutCatalog.label(for: $0.id, preferences: preferences))"
                                .localizedCaseInsensitiveContains(query))
                }
                if !rows.isEmpty {
                    SettingsGroup(group) {
                        ForEach(rows) { definition in
                            row(definition)
                        }
                    }
                }
            }
            if capturingID != nil {
                ShortcutEventCapture(active: true, onEvent: receive)
                    .frame(width: 1, height: 1)
                    .accessibilityLabel("Recording keyboard shortcut")
            }
        }
        .onDisappear { cancel() }
    }

    private func row(_ definition: KeyboardShortcutDefinition) -> some View {
        let current = KeyboardShortcutCatalog.binding(for: definition.id, preferences: preferences)
        let recording = capturingID == definition.id
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Text(definition.title)
                    .textRole(.bodyStrong, lineBox: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let current {
                    HStack(spacing: Space.s2) {
                        ForEach(current.strokes.indices, id: \.self) { index in
                            if index > 0 { Text("then").foregroundStyle(Theme.inkMuted) }
                            Kbd(KeyboardShortcutCatalog.label(for: ShortcutBinding(current.strokes[index])))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "Shortcut \(KeyboardShortcutCatalog.label(for: definition.id, preferences: preferences))")
                } else {
                    Text("Not set").foregroundStyle(Theme.inkMuted)
                }
                Button(recording ? "Cancel" : "Rebind") {
                    if recording {
                        cancel()
                    } else {
                        preferences.isRecordingShortcut = true
                        capturingID = definition.id
                        firstStroke = nil
                        message = nil
                    }
                }
                .accessibilityLabel("\(recording ? "Cancel recording" : "Rebind") \(definition.title)")
                Button("Clear") { apply(nil, to: definition.id) }
                    .disabled(current == nil)
                    .accessibilityLabel("Clear \(definition.title) shortcut")
                Button("Reset") { reset(definition.id) }
                    .disabled(preferences.shortcutOverrides[definition.id] == nil)
                    .accessibilityLabel("Reset \(definition.title) shortcut to default")
            }
            if recording {
                HStack {
                    Text(
                        firstStroke.map {
                            "First key: \(KeyboardShortcutCatalog.label(for: ShortcutBinding($0))). "
                                + "Press a second key or save one key."
                        } ?? "Press the first key for \(definition.title). Escape cancels."
                    )
                    .foregroundStyle(Theme.inkBody)
                    if let firstStroke {
                        Button("Save One Key") { apply(ShortcutBinding(firstStroke), to: definition.id) }
                    }
                }
                .accessibilityElement(children: .contain)
            }
            Hairline()
        }
        .padding(.vertical, Space.s2)
        .accessibilityElement(children: .contain)
    }

    private func receive(_ event: NSEvent) {
        guard let id = capturingID else { return }
        if event.keyCode == 53 {
            cancel()
            return
        }
        guard !event.isARepeat, let stroke = ShortcutStroke(event: event) else { return }
        if let firstStroke {
            apply(ShortcutBinding(firstStroke, stroke), to: id)
        } else {
            firstStroke = stroke
            message = nil
        }
    }

    private func apply(_ binding: ShortcutBinding?, to id: String) {
        switch KeyboardShortcutCatalog.set(binding, for: id, preferences: preferences) {
        case .success:
            message = binding.map { "Saved \(KeyboardShortcutCatalog.label(for: $0))." } ?? "Shortcut cleared."
            cancel(keepMessage: true)
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    private func reset(_ id: String) {
        switch KeyboardShortcutCatalog.reset(for: id, preferences: preferences) {
        case .success:
            message = "Shortcut reset to default."
            cancel(keepMessage: true)
        case .failure(let error): message = error.localizedDescription
        }
    }

    private func resetAll() {
        KeyboardShortcutCatalog.resetAll(preferences: preferences)
        message = "All shortcuts reset to defaults."
        cancel(keepMessage: true)
    }

    private func cancel(keepMessage: Bool = false) {
        capturingID = nil
        preferences.isRecordingShortcut = false
        firstStroke = nil
        if !keepMessage { message = nil }
    }
}

/// An NSView first responder records real keystrokes (including command equivalents), never typed text.
private struct ShortcutEventCapture: NSViewRepresentable {
    let active: Bool
    let onEvent: (NSEvent) -> Void

    func makeNSView(context: Context) -> ShortcutRecordingView {
        let view = ShortcutRecordingView()
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ view: ShortcutRecordingView, context: Context) {
        view.onEvent = onEvent
        view.active = active
        view.focusIfNeeded()
    }

}

/// Main-window dispatch must pass through keystrokes while this recorder is first responder.
final class ShortcutRecordingView: NSView {
    var onEvent: ((NSEvent) -> Void)?
    var active = false
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }

    func focusIfNeeded() {
        guard active, let window, window.firstResponder !== self else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) { onEvent?(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onEvent?(event)
        return true
    }
}
