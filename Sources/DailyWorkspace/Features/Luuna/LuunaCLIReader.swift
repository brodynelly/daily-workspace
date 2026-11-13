import DailyCore
import Foundation

/// Only the fixed-argv helper's stdout is decoded. The runner privately retains bounded stderr
/// solely to recognize fixed unauthorized HTTP statuses; no child text is included in errors.
protocol LuunaCommandRunning: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String]) async throws
        -> QuickPanelCommandOutput
}

extension QuickPanelCommandRunner: LuunaCommandRunning {}

protocol LuunaChunkRunning: Sendable {
    func runStreaming(
        executable: URL, arguments: [String], environment: [String: String],
        onStdout: @escaping @Sendable (Data) -> Void
    ) async throws -> QuickPanelCommandOutput
}

extension QuickPanelCommandRunner: LuunaChunkRunning {}

/// Read-only Luuna runtime access. A connection is captured by the caller from its current Keychain
/// settings; neither the token nor child output is included in errors or logs.
struct LuunaCLIReader: LuunaRuntimeReading {
    static let timeout: TimeInterval = 10
    static let outputLimit = 2 * 1024 * 1024

    private let executable: URL
    private let runner: any LuunaCommandRunning
    private let streamer: any LuunaChunkRunning

    init(
        executable: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/lu"),
        runner: any LuunaCommandRunning = QuickPanelCommandRunner(
            timeout: LuunaCLIReader.timeout, outputLimit: LuunaCLIReader.outputLimit),
        streamer: any LuunaChunkRunning = QuickPanelCommandRunner(
            timeout: LuunaCLIReader.timeout, outputLimit: LuunaCLIReader.outputLimit)
    ) {
        self.executable = executable
        self.runner = runner
        self.streamer = streamer
    }

    func health(_ connection: LuunaConnection) async throws -> LuunaHealth {
        try await read(["health", "--json"], connection)
    }

    func projects(_ connection: LuunaConnection) async throws -> [LuunaProjectRecord] {
        try await read(["projects", "--json"], connection)
    }

    func project(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaProjectView {
        try await read(["project", projectID, "--json"], connection)
    }

    func components(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaComponentStatus {
        try await read(["components", projectID, "--json"], connection)
    }

    func board(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaBoard {
        try await read(["board", "--project", projectID, "--json"], connection)
    }

    func tickets(_ projectID: String, _ connection: LuunaConnection) async throws -> [LuunaTicketRecord] {
        try await read(["tickets", projectID, "--json"], connection)
    }

    func showTicket(_ ticketID: String, _ connection: LuunaConnection) async throws -> LuunaTicketRecord {
        try await read(["show-ticket", ticketID, "--json"], connection)
    }

    func home(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaHome {
        try await read(["home", "--project", projectID, "--json"], connection)
    }

    func homeAll(_ connection: LuunaConnection) async throws -> LuunaHome {
        try await read(["home", "--json"], connection)
    }
    func runs(_ projectID: String, _ connection: LuunaConnection) async throws -> [LuunaRunRecord] {
        try await read(["runs", "--project", projectID, "--json"], connection)
    }

    func run(_ runID: String, _ connection: LuunaConnection) async throws -> LuunaRunRecord {
        try await read(["run", runID, "--json"], connection)
    }

    func follow(
        _ runID: String, after sequence: Int, _ connection: LuunaConnection,
        onChunk: @escaping @Sendable (Data) -> Void
    ) async throws {
        guard sequence >= 0 else { throw LuunaReadFailure.refused(LuunaRefusal(status: 0, reason: nil)) }
        let arguments = ["follow", runID, "--after", String(sequence), "--json"]
        let output = try await run(arguments, environment: validatedEnvironment(for: connection), onStdout: onChunk)
        try Task.checkCancellation()
        guard output.exitStatus == 0 else {
            if output.exitStatus == 1 && output.hasUnauthorizedHTTPStatusInStderr {
                throw LuunaReadFailure.unauthorized
            }
            throw Self.classify(output.stdout, exitStatus: output.exitStatus, command: "follow")
        }
    }

    private func read<Value: Decodable>(_ arguments: [String], _ connection: LuunaConnection) async throws -> Value {
        let environment = try validatedEnvironment(for: connection)
        let output = try await run(arguments, environment: environment)
        try Task.checkCancellation()
        guard output.exitStatus == 0 else {
            if output.exitStatus == 1 && output.hasUnauthorizedHTTPStatusInStderr {
                throw LuunaReadFailure.unauthorized
            }
            throw Self.classify(output.stdout, exitStatus: output.exitStatus, command: arguments[0])
        }
        do {
            return try JSONDecoder().decode(Value.self, from: output.stdout)
        } catch {
            throw LuunaReadFailure.undecodable
        }
    }

    private func validatedEnvironment(for connection: LuunaConnection) throws -> [String: String] {
        // Do not trust an environment setting or bypass the origin parser: the CLI gets exactly this
        // validated loopback address. Its own HTTP client rejects redirects before reusing the token.
        let origin = connection.origin.description
        guard (try? LuunaOrigin(validating: origin)) == connection.origin else {
            throw LuunaReadFailure.unsupported
        }
        guard !connection.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LuunaReadFailure.unauthorized
        }
        guard executable.isFileURL, executable.path.hasPrefix("/") else {
            throw LuunaReadFailure.unsupported
        }
        return ["LUUNA_URL": origin, "LUUNA_API_TOKEN": connection.token]
    }

    private func run(
        _ arguments: [String], environment: [String: String],
        onStdout: (@Sendable (Data) -> Void)? = nil
    ) async throws -> QuickPanelCommandOutput {
        try Task.checkCancellation()
        do {
            if let onStdout {
                return try await streamer.runStreaming(
                    executable: executable, arguments: arguments, environment: environment, onStdout: onStdout)
            }
            return try await runner.run(executable: executable, arguments: arguments, environment: environment)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as QuickPanelCommandError {
            try Task.checkCancellation()
            switch error {
            case .invalidExecutable, .launchFailed: throw LuunaReadFailure.unsupported
            case .invalidArguments: throw LuunaReadFailure.refused(LuunaRefusal(status: 0, reason: nil))
            case .timedOut: throw LuunaReadFailure.unavailable(.timedOut)
            case .outputTooLarge: throw LuunaReadFailure.undecodable
            case .ioFailed, .signaled, .exited: throw LuunaReadFailure.unavailable(.cannotConnect)
            }
        } catch {
            try Task.checkCancellation()
            throw LuunaReadFailure.unavailable(.cannotConnect)
        }
    }

    private static let maximumErrorLength = 4_000
    /// `lu --json` normally prints a single `{ "error": "<Action> refused: ..." }` on exit 1.
    /// Only fixed CLI wording or an HTTP status is used; runtime reasons are never returned to the UI.
    static func classify(_ stdout: Data, exitStatus: Int32, command: String) -> LuunaReadFailure {
        guard exitStatus != 2 else { return .unsupported }
        guard exitStatus == 1,
            let object = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any],
            let message = object["error"] as? String, message.utf16.count <= maximumErrorLength
        else { return .unavailable(.cannotConnect) }
        return classifyMessage(message.lowercased(), command: command)
    }

    private static func classifyMessage(_ text: String, command: String) -> LuunaReadFailure {
        if text.contains("rejected this token") || text.contains("runtime denied this action")
            || text.contains("http 401") || text.contains("http 403")
        {
            return .unauthorized
        }
        if text.contains("runtime did not answer") || text.contains("runtime could not be reached") {
            return .unavailable(.cannotConnect)
        }
        if text.contains("runtime no longer has this record") {
            // The CLI uses the same 404 wording for a missing route and a missing record.
            return missingRecord(command)
        }
        if text.contains("http 405") || text.contains("http 501") { return .unsupported }
        if text.contains("runtime already has four active runs") { return .unavailable(.busy) }
        if text.contains("shutting down") { return .unavailable(.shuttingDown("Runtime is shutting down.")) }
        if let status = httpStatus(in: text) {
            return classifyHTTPStatus(status, command: command)
        }
        return .refused(LuunaRefusal(status: 0, reason: nil))
    }

    private static func classifyHTTPStatus(_ status: Int, command: String) -> LuunaReadFailure {
        switch status {
        case 401, 403: return .unauthorized
        case 404: return missingRecord(command)
        case 405, 501: return .unsupported
        case 429: return .unavailable(.busy)
        case 500...599: return .unavailable(.serverError(status: status))
        default: return .refused(LuunaRefusal(status: status, reason: nil))
        }
    }

    private static func missingRecord(_ command: String) -> LuunaReadFailure {
        isRecordCommand(command) ? .refused(LuunaRefusal(status: 404, reason: nil)) : .unsupported
    }

    private static func isRecordCommand(_ command: String) -> Bool {
        command == "project" || command == "components" || command == "tickets"
            || command == "show-ticket" || command == "run"
    }

    private static func httpStatus(in text: String) -> Int? {
        guard let range = text.range(of: "http "), text[range.upperBound...].count >= 3 else { return nil }
        let digits = text[range.upperBound...].prefix(3)
        guard digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }
}
