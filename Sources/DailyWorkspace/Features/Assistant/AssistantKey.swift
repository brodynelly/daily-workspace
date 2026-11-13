import DailyCore
import Foundation

/// Whether the selected provider has an API key in the Keychain. The key itself is never kept here:
/// `AssistantSession` reads its provider-specific entry for each request.
@MainActor
final class AssistantKey: ObservableObject {
    @Published private(set) var isSaved = false
    /// Why the Keychain could not be read; nil after a successful read.
    @Published private(set) var readError: String?
    @Published private(set) var isChecking = false

    private let store: APIKeyStore
    private let openRouterStore: APIKeyStore
    private let backgroundReads: Bool
    private var refreshGeneration = 0
    private var provider: AssistantProvider = .anthropic

    init(
        store: APIKeyStore, backgroundReads: Bool = false,
        openRouterStore: APIKeyStore = KeychainAPIKeyStore(service: AssistantSession.openRouterKeyService)
    ) {
        self.store = store
        self.openRouterStore = openRouterStore
        self.backgroundReads = backgroundReads
        refresh()
    }

    func setProvider(_ selected: AssistantProvider) {
        guard provider != selected else { return }
        provider = selected
        refreshGeneration += 1
        isChecking = false
        isSaved = false
        readError = nil
        refresh()
    }

    private var currentStore: APIKeyStore { provider == .anthropic ? store : openRouterStore }

    func refresh() {
        guard backgroundReads else {
            do {
                let key = try currentStore.read()?.trimmingCharacters(in: .whitespacesAndNewlines)
                isSaved = key?.isEmpty == false
                readError = nil
            } catch {
                Log.assistant.error("Assistant key could not be read: \(Log.code(error), privacy: .public)")
                readError = "The Keychain could not be read: \(error.localizedDescription)"
            }
            return
        }
        guard !isChecking else { return }
        isChecking = true
        refreshGeneration += 1
        let generation = refreshGeneration
        let store = currentStore
        Task.detached { [weak self] in
            let saved: Bool
            let failure: String?
            do {
                let key = try store.read()?.trimmingCharacters(in: .whitespacesAndNewlines)
                saved = key?.isEmpty == false
                failure = nil
            } catch {
                saved = false
                failure = error.localizedDescription
                Log.assistant.error("Assistant key could not be read: \(Log.code(error), privacy: .public)")
            }
            await self?.finishRefresh(generation: generation, saved: saved, failure: failure)
        }
    }

    private func finishRefresh(generation: Int, saved: Bool, failure: String?) {
        guard refreshGeneration == generation else { return }
        isSaved = saved
        readError = failure.map { "The Keychain could not be read: \($0)" }
        isChecking = false
    }

    /// Store `key` (trimmed). An empty key removes it.
    func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try currentStore.save(trimmed)
        if backgroundReads {
            refreshGeneration += 1
            isChecking = false
            isSaved = !trimmed.isEmpty
            readError = nil
        } else {
            refresh()
        }
    }

    func remove() throws { try save("") }
}
