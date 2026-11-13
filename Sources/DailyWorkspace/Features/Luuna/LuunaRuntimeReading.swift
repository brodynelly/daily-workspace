import DailyCore
import Foundation
import OSLog

extension Log {
    static let luuna = Logger(subsystem: subsystem, category: "luuna")
}

extension KeychainAPIKeyStore {
    /// The Keychain service holding the Luuna runtime's bearer token. The token is never written to a file.
    static let luunaService = "app.dailyworkspace.luuna"
    static var luuna: KeychainAPIKeyStore { KeychainAPIKeyStore(service: luunaService) }
}

extension LuunaOriginError: LocalizedError {
    /// The TypeScript client's sentences for the same refusals.
    public var errorDescription: String? {
        switch self {
        case .malformed: return "That is not a valid runtime URL."
        case .notHTTPLoopback: return "Use an HTTP loopback runtime URL (127.0.0.1, localhost or [::1])."
        case .notBareOrigin: return "Runtime URL must contain only a loopback address and optional port."
        }
    }
}

/// The origin and bearer token of one connection session. The token never appears in descriptions or mirrors,
/// so it cannot reach a log line or a test failure message.
struct LuunaConnection: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    let origin: LuunaOrigin
    let token: String

    var description: String { "LuunaConnection(\(origin), token: <redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["origin": origin]) }
}

/// Read-only access through the verified `lu --json` CLI to an existing Luuna runtime:
/// health, project list/detail and component status. No method starts or changes the runtime.
/// Calls throw `LuunaReadFailure` or `CancellationError`.
protocol LuunaRuntimeReading: Sendable {
    func health(_ connection: LuunaConnection) async throws -> LuunaHealth
    func projects(_ connection: LuunaConnection) async throws -> [LuunaProjectRecord]
    func project(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaProjectView
    func components(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaComponentStatus
}
