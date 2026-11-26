import AppKit
import DailyCore
import SwiftUI

/// Whether the `?` AI pane is open. The conversation and draft are the shared Assistant's, not the panel's.
@MainActor
final class QuickPanelAssistantPane: ObservableObject {
    @Published var isVisible = false
}

extension QuickPanelController {
    var assistantVisible: Bool { assistantPane.isVisible }

    /// `?` opens the AI pane beside the results; a second `?` (outside the field) or Escape closes it.
    func toggleAssistantPane() {
        if assistantPane.isVisible {
            closeAssistantPane()
            return
        }
        zoomed = false
        assistantPane.isVisible = true
        focusedPane = "assistant"
        model?.assistantKey.refresh()
        model?.syncAssistantVaultAgents()
        objectWillChange.send()
    }

    func closeAssistantPane() {
        guard assistantPane.isVisible else { return }
        assistantPane.isVisible = false
        if focusedPane == "assistant" { focusedPane = "document" }
        objectWillChange.send()
    }

    /// Sends the shared draft only on an explicit Return. No page focus is attached from the panel.
    func sendAssistantDraft() {
        guard let model else { return }
        model.assistant.send(model.navigation.assistantDraft)
        // Keep the draft when nothing was sent (Assistant off, no key, empty question).
        if model.assistant.isStreaming { model.navigation.assistantDraft = "" }
    }

    /// Keys while the AI field has focus. `nil` lets the panel's normal handling continue (⌘W and so on);
    /// `false` passes the key to the text field.
    func handleAssistantKey(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> Bool? {
        let command = modifiers.contains(.command)
        switch keyCode {
        case 53:
            closeAssistantPane()
            return true
        case 36,
            76 where !modifiers.contains(.shift) && !command:
            sendAssistantDraft()
            return true
        case 48:
            cyclePane(reverse: modifiers.contains(.shift))
            return true
        default:
            if command && characters == "." {
                model?.assistant.stop()
                return true
            }
            return command ? nil : false
        }
    }
}

/// The `?` AI pane, drawn like the music Library sidebar.
@MainActor
struct QuickPanelAssistantPaneView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var assistant: AssistantSession
    @ObservedObject var key: AssistantKey
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var preferences: Preferences
    @FocusState private var fieldFocused: Bool
    private typealias Ink = QuickPanelPascalSkin.Ink

    private var isConnected: Bool { preferences.assistantEnabled && key.isSaved }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Ink.gold)
                Text(isConnected ? "\(preferences.selectedAssistantModel)" : "AI is off")
                    .foregroundStyle(Ink.meta)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Expand") { controller.toggleAIPopup() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.cyan)
                    .help("Open the AI chat popup (⌘J)")
                if !assistant.turns.isEmpty {
                    Button("New") {
                        assistant.clear()
                        navigation.assistantDraft = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.cyan)
                    .help("Start a new conversation")
                }
            }
            .font(.system(size: 11, design: .monospaced))
            Rectangle().fill(Ink.idleRule.opacity(0.5)).frame(height: 1)
            if isConnected {
                transcript
                if let error = assistant.error {
                    Text(error).foregroundStyle(Ink.coral).font(.system(size: 11)).lineLimit(3)
                }
                input
            } else {
                disconnected
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { syncFocus() }
        .onChange(of: controller.focusedPane) { _, _ in syncFocus() }
        .accessibilityLabel("AI chat")
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if assistant.turns.isEmpty && !assistant.isStreaming {
                        Text("Ask about your projects, notes or calendar. Answers cite their sources.")
                            .foregroundStyle(Ink.meta)
                    }
                    ForEach(assistant.turns) { turn in
                        exchange(question: turn.question, answer: turn.answer, sources: turn.citations.count)
                    }
                    if assistant.isStreaming {
                        exchange(
                            question: assistant.pendingQuestion ?? "",
                            answer: assistant.liveText.isEmpty ? "Thinking…" : assistant.liveText, sources: 0)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.trailing, 4)
            }
            .onChange(of: assistant.liveText) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: assistant.turns.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .frame(maxHeight: .infinity)
    }

    private func exchange(question: String, answer: String, sources: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("> \(question)").foregroundStyle(Ink.gold)
            QuickPanelMarkdownView(text: answer, compact: true)
            if sources > 0 {
                Text("\(sources) \(sources == 1 ? "source" : "sources") · open Assistant for citations")
                    .foregroundStyle(Ink.meta).font(.system(size: 10))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(">").foregroundStyle(Ink.title)
                TextField("Ask AI…", text: $navigation.assistantDraft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onTapGesture { controller.focusedPane = "assistant" }
                    .accessibilityLabel("Ask AI")
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .overlay(
                Rectangle().strokeBorder(
                    controller.focusedPane == "assistant" ? Ink.activeRule : Ink.idleRule, lineWidth: 1))
            HStack(spacing: 12) {
                QuickPanelKeyCaps(keys: "↵", label: "Ask")
                if assistant.isStreaming { QuickPanelKeyCaps(keys: "⌘.", label: "Stop") }
                QuickPanelKeyCaps(keys: "esc", label: "Close")
            }
        }
    }

    private var disconnected: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                preferences.assistantEnabled
                    ? "Add an API key in Settings → AI to chat here."
                    : "The Assistant is off. Turn it on in Settings → AI. Nothing is sent until you do."
            )
            .foregroundStyle(Ink.meta)
            .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings → AI") {
                navigation.showSettings(tab: .ai)
                controller.open(navigation.section)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.cyan)
            Spacer(minLength: 0)
        }
    }

    private func syncFocus() {
        let wanted = controller.focusedPane == "assistant"
        DispatchQueue.main.async { fieldFocused = wanted }
    }
}

/// Key strokes drawn as separate caps (`^B D` → ⌃B · D) with an optional label.
@MainActor
struct QuickPanelKeyCaps: View {
    let keys: String
    var label: String = ""
    private typealias Ink = QuickPanelPascalSkin.Ink

    static func strokes(_ keys: String) -> [String] {
        let trimmed = keys.trimmingCharacters(in: .whitespaces)
        // "j/k"-style alternatives and single glyphs stay together; spaces separate strokes.
        return trimmed.split(separator: " ").map { stroke in
            stroke.hasPrefix("^") && stroke.count > 1 ? "⌃" + stroke.dropFirst() : String(stroke)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(Array(Self.strokes(keys).enumerated()), id: \.offset) { _, stroke in
                    Text(stroke)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.gold)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 17)
                        .background(Ink.header.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Ink.idleRule.opacity(0.55), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            if !label.isEmpty {
                Text(label.trimmingCharacters(in: .whitespaces)).foregroundStyle(Ink.footer)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? keys : "\(keys) \(label)")
    }
}
