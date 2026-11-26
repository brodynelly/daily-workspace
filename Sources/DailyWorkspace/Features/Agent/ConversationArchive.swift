import CryptoKit
import DailyCore
import Foundation

/// Saved Assistant conversations, one file per conversation under `~/.config/daily-workspace/agent/conversations`,
/// each sealed with AES-GCM under a 256-bit key kept in the login Keychain (never on disk). Transcripts are kept
/// byte-for-byte, so a resumed conversation replays its thinking blocks unchanged.
///
/// Off when Settings → AI → Agent → Save conversations is off: nothing is written, and turning it off does not
/// delete what is saved (Delete all history does). Files older than the retention period are deleted at launch.
@MainActor
final class ConversationArchive: ObservableObject {
    /// Saved conversations, newest first.
    @Published private(set) var conversations: [AssistantConversation] = []
    /// Files that could not be opened (a lost key or a damaged file); they are left in place.
    @Published private(set) var unreadable = 0
    @Published private(set) var storageError: String?

    private let folder: URL
    private let keyStore: APIKeyStore
    private let isEnabled: () -> Bool
    private let retentionDays: () -> Int
    private let now: () -> Date
    private var cipher: ConversationCipher?

    nonisolated static let keyService = "app.dailyworkspace.agent-history"
    static let fileExtension = "chat"

    init(
        folder: URL, keyStore: APIKeyStore, isEnabled: @escaping () -> Bool,
        retentionDays: @escaping () -> Int = { 180 }, now: @escaping () -> Date = { Date() }
    ) {
        self.folder = folder
        self.keyStore = keyStore
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
        self.now = now
    }

    /// Read every saved conversation, deleting those past retention.
    func load() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            conversations = []
            return
        }
        let cutoff = now().addingTimeInterval(-Double(retentionDays()) * 86_400)
        var loaded: [AssistantConversation] = []
        var failed = 0
        for name in names where name.hasSuffix("." + Self.fileExtension) {
            let url = folder.appendingPathComponent(name)
            do {
                guard let sealed = try PrivateFile.read(url) else { continue }
                let data = try cipherForUse(create: false).open(sealed)
                let conversation = try PrivateFile.decoder().decode(StoredConversation.self, from: data).conversation
                if conversation.archivedAt < cutoff {
                    try? FileManager.default.removeItem(at: url)
                } else {
                    loaded.append(conversation)
                }
            } catch {
                failed += 1
            }
        }
        unreadable = failed
        conversations = loaded.sorted { $0.archivedAt > $1.archivedAt }
    }

    /// Save `conversation`, replacing its earlier version. One with no turns and nothing running is removed.
    func save(_ conversation: AssistantConversation) {
        guard isEnabled() else { return }
        conversations.removeAll { $0.id == conversation.id }
        guard !conversation.turns.isEmpty || conversation.interruptedQuestion != nil else {
            try? FileManager.default.removeItem(at: url(for: conversation.id))
            return
        }
        do {
            let data = try PrivateFile.encoder().encode(StoredConversation(conversation))
            try PrivateFile.write(try cipherForUse(create: true).seal(data), to: url(for: conversation.id))
            conversations.insert(conversation, at: 0)
            storageError = nil
        } catch {
            Log.assistant.error("A conversation could not be saved: \(Log.code(error), privacy: .public)")
            storageError = "Chat history could not be saved."
        }
    }

    func conversation(_ id: UUID) -> AssistantConversation? {
        conversations.first { $0.id == id }
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
        conversations.removeAll { $0.id == id }
    }

    /// Delete every saved conversation and the key that sealed them.
    func deleteAll() {
        if let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for name in names where name.hasSuffix("." + Self.fileExtension) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        try? keyStore.save("")
        cipher = nil
        conversations = []
        unreadable = 0
    }

    private func url(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)")
    }

    private func cipherForUse(create: Bool) throws -> ConversationCipher {
        if let cipher { return cipher }
        let made = try ConversationCipher(keyStore: keyStore, create: create)
        cipher = made
        return made
    }
}

/// AES-GCM sealing with a random 256-bit key stored (base64) in the Keychain.
struct ConversationCipher {
    let key: SymmetricKey

    struct MissingKey: Error {}

    init(key: SymmetricKey) {
        self.key = key
    }

    /// The saved key, or a new one saved now when `create` is true.
    init(keyStore: APIKeyStore, create: Bool) throws {
        if let saved = try keyStore.read(), let data = Data(base64Encoded: saved), data.count == 32 {
            key = SymmetricKey(data: data)
            return
        }
        guard create else { throw MissingKey() }
        let fresh = SymmetricKey(size: .bits256)
        try keyStore.save(fresh.withUnsafeBytes { Data($0) }.base64EncodedString())
        key = fresh
    }

    func seal(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw CryptoKitError.incorrectKeySize }
        return combined
    }

    func open(_ data: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }
}

/// The on-disk shape of a conversation. Content blocks are stored as their exact bytes.
private struct StoredConversation: Codable {
    struct Message: Codable {
        let role: String
        let content: [Data]
    }

    struct Citation: Codable {
        let kind: String
        let value: String

        var citation: ToolCitation? {
            ToolCitation.Kind(rawValue: kind).map { ToolCitation(kind: $0, value: value) }
        }
    }

    struct ToolCall: Codable {
        let id: String
        let name: String
        let arguments: String
        let isError: Bool
        let errorMessage: String?
        let citations: [Citation]
    }

    struct Usage: Codable {
        let input: Int
        let output: Int
        let cacheWrite: Int
        let cacheRead: Int
    }

    struct Turn: Codable {
        let id: UUID
        let question: String
        let answer: String
        let finalAnswer: String
        let toolCalls: [ToolCall]
        let askedAt: Date
        let fallbackModel: String?
        let usage: Usage
        let contextTokens: Int
    }

    var version = 1
    let id: UUID
    let provider: AssistantProvider
    let model: String
    let contextFingerprint: String
    let startedAt: Date
    let archivedAt: Date
    let origin: String
    let interruptedQuestion: String?
    let messages: [Message]
    let turns: [Turn]

    init(_ conversation: AssistantConversation) {
        id = conversation.id
        provider = conversation.provider
        model = conversation.model
        contextFingerprint = conversation.contextFingerprint
        startedAt = conversation.startedAt
        archivedAt = conversation.archivedAt
        origin = conversation.origin
        interruptedQuestion = conversation.interruptedQuestion
        messages = conversation.transcript.map { Message(role: $0.role.rawValue, content: $0.content) }
        turns = conversation.turns.map { turn in
            Turn(
                id: turn.id, question: turn.question, answer: turn.answer, finalAnswer: turn.finalAnswer,
                toolCalls: turn.toolCalls.map { call in
                    ToolCall(
                        id: call.id, name: call.name, arguments: call.arguments, isError: call.isError,
                        errorMessage: call.errorMessage,
                        citations: call.citations.map { Citation(kind: $0.kind.rawValue, value: $0.value) })
                },
                askedAt: turn.askedAt, fallbackModel: turn.fallbackModel,
                usage: Usage(
                    input: turn.usage.inputTokens, output: turn.usage.outputTokens,
                    cacheWrite: turn.usage.cacheCreationInputTokens, cacheRead: turn.usage.cacheReadInputTokens),
                contextTokens: turn.contextTokens)
        }
    }

    var conversation: AssistantConversation {
        let transcript = messages.compactMap { message in
            AgentMessage.Role(rawValue: message.role).map { AgentMessage(role: $0, content: message.content) }
        }
        let turns = self.turns.map { turn in
            var made = AssistantTurn(
                id: turn.id, question: turn.question, answer: turn.answer, finalAnswer: turn.finalAnswer,
                toolCalls: turn.toolCalls.map { call in
                    AssistantToolCall(
                        id: call.id, name: call.name, arguments: call.arguments, isError: call.isError,
                        errorMessage: call.errorMessage,
                        citations: call.citations.compactMap(\.citation))
                },
                askedAt: turn.askedAt, fallbackModel: turn.fallbackModel)
            made.usage = AgentUsage(
                inputTokens: turn.usage.input, outputTokens: turn.usage.output,
                cacheCreationInputTokens: turn.usage.cacheWrite, cacheReadInputTokens: turn.usage.cacheRead)
            made.contextTokens = turn.contextTokens
            return made
        }
        var conversation = AssistantConversation(
            id: id, turns: turns, transcript: transcript, provider: provider, model: model,
            contextFingerprint: contextFingerprint, startedAt: startedAt, archivedAt: archivedAt)
        conversation.origin = origin
        conversation.interruptedQuestion = interruptedQuestion
        return conversation
    }
}
