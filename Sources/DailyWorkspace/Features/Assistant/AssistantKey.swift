import Foundation

/// Whether an Anthropic API key is saved in the Keychain, for Settings and the Assistant screen. The key itself
/// is never kept here: `AssistantSession` reads it from the store for each request.
@MainActor
final class AssistantKey: ObservableObject {
    @Published private(set) var isSaved = false
    /// Why the Keychain could not be read; nil after a successful read.
    @Published private(set) var readError: String?

    private let store: APIKeyStore

    init(store: APIKeyStore) {
        self.store = store
        refresh()
    }

    func refresh() {
        do {
            let key = try store.read()?.trimmingCharacters(in: .whitespacesAndNewlines)
            isSaved = key?.isEmpty == false
            readError = nil
        } catch {
            Log.chat.error("Anthropic key could not be read: \(Log.code(error), privacy: .public)")
            readError = "The Keychain could not be read: \(error.localizedDescription)"
        }
    }

    /// Store `key` (trimmed). An empty key removes it.
    func save(_ key: String) throws {
        defer { refresh() }
        try store.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func remove() throws {
        defer { refresh() }
        try store.save("")
    }
}
