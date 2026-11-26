import AppKit
import DailyCore
import Foundation

/// A model the selected provider's API reports.
struct QuickPanelModelOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// State for the Raycast-style AI chat popup over the quick panel. The conversation and draft are the
/// shared Assistant's; this only tracks which layer (chat, actions, model list) has the keyboard.
@MainActor
final class QuickPanelAIPopup: ObservableObject {
    enum Layer: Equatable { case chat, actions, models }

    @Published private(set) var isVisible = false
    @Published var layer: Layer = .chat
    @Published var listQuery = "" { didSet { listIndex = 0 } }
    @Published var listIndex = 0
    @Published private(set) var models: [QuickPanelModelOption] = []
    @Published private(set) var modelsStatus: String?
    @Published var notice: String?
    private var modelsProvider: AssistantProvider?

    func open() {
        layer = .chat
        listQuery = ""
        notice = nil
        isVisible = true
    }

    func close() {
        isVisible = false
        layer = .chat
        listQuery = ""
    }

    func show(_ next: Layer) {
        layer = layer == next ? .chat : next
        listQuery = ""
    }

    func setModels(_ options: [QuickPanelModelOption], provider: AssistantProvider) {
        models = options
        modelsProvider = provider
        modelsStatus = options.isEmpty ? "The API returned no models" : nil
    }

    func setModelsStatus(_ status: String?) { modelsStatus = status }

    func needsModels(for provider: AssistantProvider) -> Bool { modelsProvider != provider || models.isEmpty }
}

/// Lists models with the user's own key, only after they open the model picker.
enum QuickPanelModelCatalog {
    static func request(provider: AssistantProvider, key: String) -> URLRequest {
        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1000")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(AnthropicClient.apiVersion, forHTTPHeaderField: "anthropic-version")
        case .openRouter:
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// Both APIs answer `{"data": [{"id": …, "display_name" | "name": …}]}`.
    static func parse(_ data: Data, provider: AssistantProvider) throws -> [QuickPanelModelOption] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["data"] as? [[String: Any]]
        else { throw URLError(.cannotParseResponse) }
        let options = items.compactMap { item -> QuickPanelModelOption? in
            guard let id = item["id"] as? String, !id.isEmpty, id.count <= 200 else { return nil }
            let name = (item["display_name"] as? String) ?? (item["name"] as? String) ?? id
            return QuickPanelModelOption(id: id, name: name)
        }
        // Anthropic lists newest first; OpenRouter's list is long, so sort it for scanning.
        return provider == .openRouter ? options.sorted { $0.id < $1.id } : options
    }

    static func fetch(provider: AssistantProvider, key: String) async throws -> [QuickPanelModelOption] {
        let (data, response) = try await URLSession.shared.data(for: request(provider: provider, key: key))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try parse(data, provider: provider)
    }
}

/// One row in the popup's action or slash-command list.
struct QuickPanelAIAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var keys = ""
    var destructive = false
    let perform: @MainActor () -> Void
}

extension QuickPanelController {
    func toggleAIPopup() {
        if aiPopup.isVisible {
            aiPopup.close()
        } else {
            palette.close()
            aiPopup.open()
            model?.assistantKey.refresh()
            model?.syncAssistantVaultAgents()
        }
        objectWillChange.send()
    }

    var aiActions: [QuickPanelAIAction] {
        let assistant = model?.assistant
        var actions: [QuickPanelAIAction] = [
            .init(id: "new", title: "New Chat", symbol: "plus.bubble", keys: "⌘N") { [weak self] in self?.newAIChat() },
            .init(id: "model", title: "Change Model…", symbol: "cpu", keys: "⇧⌘M") { [weak self] in
                self?.showModelPicker()
            },
            .init(id: "copy", title: "Copy Last Answer", symbol: "doc.on.doc", keys: "⇧⌘C") { [weak self] in
                self?.copyLastAnswer()
            },
        ]
        if assistant?.isStreaming == true {
            actions.append(
                .init(id: "stop", title: "Stop Answer", symbol: "stop.circle", keys: "⌘.") { assistant?.stop() })
        }
        actions += [
            .init(id: "zoomIn", title: "Zoom In", symbol: "plus.magnifyingglass", keys: "⌘+") { [weak self] in
                self?.zoom(by: 1)
            },
            .init(id: "zoomOut", title: "Zoom Out", symbol: "minus.magnifyingglass", keys: "⌘-") { [weak self] in
                self?.zoom(by: -1)
            },
            .init(id: "actual", title: "Actual Size", symbol: "1.magnifyingglass", keys: "⌘0") { [weak self] in
                self?.resetZoom()
            },
            .init(id: "sidebar", title: "Show in Sidebar", symbol: "sidebar.left", keys: "?") { [weak self] in
                guard let self else { return }
                self.toggleAIPopup()
                if !self.assistantVisible { self.toggleAssistantPane() }
            },
            .init(id: "workspace", title: "Open in Daily Workspace", symbol: "macwindow") { [weak self] in
                self?.open(.assistant)
            },
            .init(id: "clear", title: "Delete Chat", symbol: "trash", keys: "⌃X", destructive: true) { [weak self] in
                self?.newAIChat()
            },
        ]
        return actions
    }

    /// `/` commands typed in the chat field.
    var aiSlashActions: [QuickPanelAIAction] {
        guard let draft = model?.navigation.assistantDraft, draft.hasPrefix("/"), !draft.contains(" ") else {
            return []
        }
        let typed = draft.dropFirst().lowercased()
        let commands: [(String, String)] = [
            ("new", "new"), ("model", "model"), ("copy", "copy"), ("stop", "stop"), ("zoom-in", "zoomIn"),
            ("zoom-out", "zoomOut"), ("reset-zoom", "actual"), ("sidebar", "sidebar"), ("open", "workspace"),
        ]
        let byID = Dictionary(uniqueKeysWithValues: aiActions.map { ($0.id, $0) })
        return commands.compactMap { name, id in
            guard typed.isEmpty || name.hasPrefix(typed), let action = byID[id] else { return nil }
            return QuickPanelAIAction(
                id: "slash:\(name)", title: "/\(name)  \(action.title)", symbol: action.symbol, keys: action.keys
            ) { [weak self] in
                self?.model?.navigation.assistantDraft = ""
                action.perform()
            }
        }
    }

    var aiModelOptions: [QuickPanelModelOption] {
        let words = aiPopup.listQuery.lowercased().split(separator: " ")
        return aiPopup.models.filter { option in
            words.allSatisfy { "\(option.id) \(option.name)".lowercased().contains($0) }
        }
    }

    var aiFilteredActions: [QuickPanelAIAction] {
        let words = aiPopup.listQuery.lowercased().split(separator: " ")
        return aiActions.filter { action in words.allSatisfy { action.title.lowercased().contains($0) } }
    }

    func newAIChat() {
        model?.assistant.clear()
        model?.navigation.assistantDraft = ""
        aiPopup.layer = .chat
        aiPopup.notice = nil
    }

    func copyLastAnswer() {
        guard let answer = model?.assistant.turns.last?.answer, !answer.isEmpty else {
            aiPopup.notice = "No answer to copy yet"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        aiPopup.notice = "Copied the last answer"
    }

    /// ⇧⌘M: list the provider's models with the user's key. Nothing is requested while the Assistant is off.
    func showModelPicker() {
        aiPopup.show(.models)
        guard aiPopup.layer == .models, let model else { return }
        let provider = model.preferences.assistantProvider
        guard aiPopup.needsModels(for: provider) else { return }
        guard model.preferences.assistantEnabled else {
            aiPopup.setModelsStatus("Turn on the Assistant in Settings → AI to list models")
            return
        }
        guard let key = model.assistant.readKey() else {
            aiPopup.setModelsStatus("Add your \(provider.title) API key in Settings → AI")
            return
        }
        aiPopup.setModelsStatus("Loading \(provider.title) models…")
        Task {
            do {
                let options = try await QuickPanelModelCatalog.fetch(provider: provider, key: key)
                aiPopup.setModels(options, provider: provider)
            } catch {
                aiPopup.setModelsStatus("Could not list \(provider.title) models")
            }
        }
    }

    /// Changing the model starts a new conversation (the Assistant never mixes models in one transcript).
    func selectModel(_ option: QuickPanelModelOption) {
        guard let model else { return }
        if model.preferences.assistantProvider == .anthropic {
            model.preferences.assistantModel = option.id
        } else {
            model.preferences.openRouterModel = option.id
        }
        model.assistant.setModel(option.id)
        aiPopup.layer = .chat
        aiPopup.notice = "Switched to \(option.name) · new chat"
    }

    func sendAIDraft() {
        if let first = aiSlashActions.first {
            first.perform()
            return
        }
        aiPopup.notice = nil
        sendAssistantDraft()
    }

    /// The popup is modal: chat keys go to its text field, list layers own typing like the ⌘K popup.
    func handleAIPopupKey(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)
        let key = characters.lowercased()
        if command, let handled = handleAIPopupCommand(key, shift: shift) { return handled }
        if keyCode == 53 {
            if aiPopup.layer != .chat {
                aiPopup.layer = .chat
            } else {
                toggleAIPopup()
            }
            return true
        }
        if aiPopup.layer != .chat {
            return handleAIListKey(keyCode: keyCode, characters: characters, modifiers: modifiers)
        }
        return handleAIChatKey(keyCode: keyCode, key: key, modifiers: modifiers)
    }

    private func handleAIChatKey(keyCode: UInt16, key: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let slash = aiSlashActions
        if !slash.isEmpty, [125, 126].contains(keyCode) {
            moveAIList(by: keyCode == 125 ? 1 : -1, count: slash.count)
            return true
        }
        if [36, 76].contains(keyCode), !modifiers.contains(.shift) {
            if slash.indices.contains(aiPopup.listIndex) {
                let action = slash[aiPopup.listIndex]
                aiPopup.listIndex = 0
                action.perform()
            } else {
                sendAIDraft()
            }
            return true
        }
        if modifiers.contains(.control) && key == "x" {
            newAIChat()
            return true
        }
        return false
    }

    private func handleAIPopupCommand(_ key: String, shift: Bool) -> Bool? {
        switch (key, shift) {
        case ("m", true): showModelPicker()
        case ("k", false): aiPopup.show(.actions)
        case ("j", false): toggleAIPopup()
        case ("n", false): newAIChat()
        case ("c", true): copyLastAnswer()
        case ("=", _), ("+", _): zoom(by: 1)
        case ("-", false): zoom(by: -1)
        case ("0", false): resetZoom()
        case (".", false): model?.assistant.stop()
        default: return nil
        }
        return true
    }

    private func runSelectedAIListRow() {
        let index = aiPopup.listIndex
        if aiPopup.layer == .models {
            let options = aiModelOptions
            if options.indices.contains(index) { selectModel(options[index]) }
        } else {
            let actions = aiFilteredActions
            guard actions.indices.contains(index) else { return }
            aiPopup.layer = .chat
            actions[index].perform()
        }
    }

    private func handleAIListKey(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let count = aiPopup.layer == .models ? aiModelOptions.count : aiFilteredActions.count
        switch keyCode {
        case 125, 48: moveAIList(by: 1, count: count)
        case 126: moveAIList(by: -1, count: count)
        case 36, 76: runSelectedAIListRow()
        case 51, 117:
            if !aiPopup.listQuery.isEmpty { aiPopup.listQuery.removeLast() }
        default:
            if modifiers.contains(.command) || modifiers.contains(.control) { return false }
            if characters.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) {
                aiPopup.listQuery += characters
            }
        }
        return true
    }

    private func moveAIList(by offset: Int, count: Int) {
        guard count > 0 else { return }
        aiPopup.listIndex = (aiPopup.listIndex + offset + count) % count
    }
}
