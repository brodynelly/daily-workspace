import Foundation

/// Earlier AI chats for this app run. They live in memory only (saving chats to disk was declined) and are
/// opened explicitly from CHATS, ⌘[ / ⌘] or Return; opening the AI page always starts a fresh chat.
extension QuickPanelAIPopup {
    func file(_ conversation: AssistantConversation) {
        chats.append(conversation)
        chats.sort { $0.startedAt > $1.startedAt }
    }

    func take(_ id: AssistantConversation.ID) -> AssistantConversation? {
        guard let index = chats.firstIndex(where: { $0.id == id }) else { return nil }
        return chats.remove(at: index)
    }

    func discard(_ id: AssistantConversation.ID) { chats.removeAll { $0.id == id } }
}

extension QuickPanelController {
    /// Files the current conversation (if any and not mid-answer) and clears it. Returns false while answering.
    @discardableResult
    func fileCurrentChat() -> Bool {
        guard let assistant = model?.assistant, !assistant.isStreaming else { return false }
        if let current = assistant.archivedConversation() { aiPopup.file(current) }
        assistant.clear()
        return true
    }

    /// Row 0 of CHATS is the current chat; rows 1… are earlier chats, newest first.
    var aiChatRowCount: Int { aiPopup.chats.count + 1 }

    func openAIChatRow(_ row: Int) {
        aiPopup.chatIndex = 0
        guard row > 0, aiPopup.chats.indices.contains(row - 1) else {
            aiPopup.section = .conversation
            return
        }
        openAIChat(aiPopup.chats[row - 1].id)
    }

    func openAIChat(_ id: AssistantConversation.ID) {
        guard let assistant = model?.assistant, !assistant.isStreaming, let chosen = aiPopup.take(id) else { return }
        if let current = assistant.archivedConversation() { aiPopup.file(current) }
        let resumed = assistant.restore(chosen)
        model?.navigation.assistantDraft = ""
        aiPopup.focusedTurn = nil
        aiPopup.chatIndex = 0
        aiPopup.section = .conversation
        aiPopup.notice =
            resumed
            ? "Opened “\(chosen.title)”"
            : "Opened “\(chosen.title)” · the model or vault changed, so follow-ups start fresh context"
    }

    /// ⌘[ opens the next older chat, ⌘] the next newer one, ordered by when each chat started.
    func stepAIChat(older: Bool) {
        guard let assistant = model?.assistant else { return }
        let currentStart = assistant.turns.first?.askedAt
        let candidates = aiPopup.chats.filter { chat in
            guard let currentStart else { return older }
            return older ? chat.startedAt < currentStart : chat.startedAt > currentStart
        }
        let next =
            older ? candidates.max { $0.startedAt < $1.startedAt } : candidates.min { $0.startedAt < $1.startedAt }
        if let next {
            openAIChat(next.id)
        } else if !older, currentStart != nil {
            fileCurrentChat()
            aiPopup.notice = "New chat"
        }
    }

    /// CHATS: j/k select, g/G jump, Return opens, x removes an earlier chat from the list.
    func handleAIChatsKey(keyCode: UInt16, key: String) -> Bool? {
        let count = aiChatRowCount
        switch key {
        case "j": aiPopup.chatIndex = min(count - 1, aiPopup.chatIndex + 1)
        case "k": aiPopup.chatIndex = max(0, aiPopup.chatIndex - 1)
        case "g": aiPopup.chatIndex = 0
        case "G": aiPopup.chatIndex = count - 1
        case "x":
            let row = aiPopup.chatIndex
            if row > 0, aiPopup.chats.indices.contains(row - 1) {
                aiPopup.discard(aiPopup.chats[row - 1].id)
                aiPopup.chatIndex = min(row, aiChatRowCount - 1)
            }
        default:
            guard [36, 76].contains(keyCode) else { return nil }
            openAIChatRow(aiPopup.chatIndex)
        }
        return true
    }
}
