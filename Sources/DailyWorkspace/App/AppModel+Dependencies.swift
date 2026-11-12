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
        var keyStore: APIKeyStore
        var chatTransport: ChatTransport
        var calendarStore: CalendarStore
        var reminderStore: ReminderStore
        /// Read-only GETs against an already running Luuna runtime.
        var luunaReader: LuunaRuntimeReading
        /// The Luuna bearer token (Keychain service `app.dailyworkspace.luuna`).
        var luunaKeyStore: APIKeyStore
        /// The Anthropic Messages API, for the Assistant. Nothing is sent while the Assistant is disabled.
        var agentTransport: AgentTransport
        /// The Anthropic API key (Keychain service `AssistantSession.keyService`).
        var assistantKeyStore: APIKeyStore
        var autosaveDelay: Duration
        /// System notifications and the external-change poll. Off in tests.
        var observesSystem: Bool

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
                keyStore: KeychainAPIKeyStore(),
                chatTransport: OpenRouterClient(),
                calendarStore: EventKitCalendarStore(),
                reminderStore: EventKitReminderStore(),
                luunaReader: LuunaRuntimeClient(),
                luunaKeyStore: KeychainAPIKeyStore.luuna,
                agentTransport: AnthropicClient(),
                assistantKeyStore: KeychainAPIKeyStore(service: AssistantSession.keyService),
                autosaveDelay: .milliseconds(800),
                observesSystem: true
            )
        }
    }

    enum CaptureDestination: String, CaseIterable, Identifiable {
        case task, note

        var id: String { rawValue }

        var title: String {
            switch self {
            case .task: return "Task for Today"
            case .note: return "Today's Note"
            }
        }
    }

    enum CaptureOutcome: Equatable {
        case captured
        case rejected(String)
    }
}
