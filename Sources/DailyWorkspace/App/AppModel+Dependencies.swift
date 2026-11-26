import DailyCore
import Foundation

extension AppModel {
    /// Everything `AppModel` is built from. `live` is the app; tests pass fakes (`Dependencies.test`).
    struct Dependencies {
        /// The app's own folder (`~/.config/daily-workspace`), shown in Settings.
        var directory: WorkspaceDirectory
        var settings: SettingsPersisting
        /// Settings from earlier versions, imported once when no settings file exists yet.
        var legacyDefaults: UserDefaults?
        var makeTaskPersistence: () throws -> TaskPersisting
        var recovery: RecoveryStoring
        var calendarStore: CalendarStore
        var reminderStore: ReminderStore
        /// Read-only fixed-argv Luuna CLI reads against the current Keychain connection.
        var luunaReader: LuunaRuntimeReading
        /// Read-only native Luuna board, tickets and Home CLI projections.
        var luunaWorkReader: any LuunaWorkReading
        /// The Luuna bearer token (Keychain service `app.dailyworkspace.luuna`).
        var luunaKeyStore: APIKeyStore
        /// Anthropic Messages transport and credential. Nothing is sent while the Assistant is disabled.
        var agentTransport: AgentTransport
        var assistantKeyStore: APIKeyStore
        /// Separate OpenRouter Messages transport and Keychain entry; fakes may override both.
        var openRouterTransport: AgentTransport = OpenRouterClient()
        var openRouterKeyStore: APIKeyStore = KeychainAPIKeyStore(
            service: AssistantSession.openRouterKeyService)
        var autosaveDelay: Duration
        /// System notifications and the external-change poll. Off in tests.
        var observesSystem: Bool
        /// The Keychain entry holding the key that seals saved conversations.
        var agentHistoryKeyStore: APIKeyStore = KeychainAPIKeyStore(service: ConversationArchive.keyService)

        @MainActor static var live: Dependencies {
            let directory = WorkspaceDirectory.standard()
            do {
                try directory.prepare()
            } catch {
                Log.app.error(
                    "Workspace folder could not be created: \(Log.code(error), privacy: .public) \(error.localizedDescription, privacy: .private(mask: .hash))"
                )
            }
            return Dependencies(
                directory: directory,
                settings: SettingsPersistence(url: directory.settingsURL),
                legacyDefaults: .standard,
                makeTaskPersistence: {
                    // Copy tasks from the old location once; the original file is left in place.
                    let legacy = WorkspaceDirectory.legacyFolder().appendingPathComponent("tasks.json")
                    if try WorkspaceDirectory.adopt(legacyFile: legacy, as: directory.tasksURL) {
                        Log.tasks.info("Copied tasks from the previous Application Support location")
                    }
                    return TaskPersistence(url: directory.tasksURL)
                },
                recovery: RecoveryStore(folder: directory.recoveryFolder),
                calendarStore: EventKitCalendarStore(),
                reminderStore: EventKitReminderStore(),
                luunaReader: LuunaCLIReader(),
                luunaWorkReader: LuunaCLIReader(),
                luunaKeyStore: KeychainAPIKeyStore.luuna,
                agentTransport: AnthropicClient(),
                assistantKeyStore: KeychainAPIKeyStore(service: AssistantSession.keyService),
                autosaveDelay: .milliseconds(800),
                observesSystem: true
            )
        }
    }

    enum CaptureDestination: String, CaseIterable, Identifiable {
        case task, note, quickNotes, inbox

        var id: String { rawValue }

        var title: String {
            switch self {
            case .task: return "Task for Today"
            case .note: return "Today's Note"
            case .quickNotes: return "Quick Notes"
            case .inbox: return "Inbox Note"
            }
        }
    }

    enum CaptureOutcome: Equatable {
        case captured
        case rejected(String)
    }
}
