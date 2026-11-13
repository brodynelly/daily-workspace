import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

/// A scripted `AgentTransport`: answers each request with the next scripted result and records every request.
final class FakeAgentTransport: AgentTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Result<AgentResponse, Error>]
    private var recorded: [AgentRequest] = []
    /// Answers requests after the script runs out (index is the request number, from 0).
    var whenScriptEnds: @Sendable (Int) -> Result<AgentResponse, Error> = { _ in
        .failure(TestFailure("unscripted request"))
    }
    /// Streamed before every response.
    var updates: [AgentStreamUpdate] = []
    /// Wait before answering (to test Stop).
    var delay: Duration?

    init(_ script: [Result<AgentResponse, Error>] = []) {
        self.script = script
    }

    var requests: [AgentRequest] { lock.withLock { recorded } }

    /// Each request body, parsed.
    var bodies: [[String: Any]] {
        requests.map { (try? JSONSerialization.jsonObject(with: $0.body())) as? [String: Any] ?? [:] }
    }

    func send(
        _ request: AgentRequest, apiKey: String, onUpdate: @escaping @Sendable (AgentStreamUpdate) async -> Void
    ) async throws -> AgentResponse {
        let next: Result<AgentResponse, Error> = lock.withLock {
            recorded.append(request)
            return script.isEmpty ? whenScriptEnds(recorded.count - 1) : script.removeFirst()
        }
        for update in updates { await onUpdate(update) }
        if let delay { try await Task.sleep(for: delay) }
        return try next.get()
    }
}

/// An `AssistantContext` over canned data that records every call.
final class FakeAssistantContext: AssistantContext, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var hits = [ToolNoteHit(path: "01-projects/alpha/hub.md", title: "Alpha", snippet: "Alpha hub")]
    var note = ToolNote(path: "01-projects/alpha/hub.md", text: "# Alpha\nShip the beta.", truncated: false)
    var rows = [
        ToolLoopRow(
            id: "local:alpha-12", source: "local", title: "Write the spec", status: "open", project: "alpha",
            path: "01-projects/alpha/hub.md", observedAt: Date(timeIntervalSince1970: 1_800_000_000))
    ]
    var events = [
        ToolEvent(
            id: "event-1", title: "Standup", start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_001_800), isAllDay: false, calendar: "Work")
    ]
    var failure: Error?

    var calls: [String] { lock.withLock { recorded } }

    private func record(_ call: String) throws {
        lock.withLock { recorded.append(call) }
        if let failure { throw failure }
    }

    func searchNotes(query: String, limit: Int) async throws -> [ToolNoteHit] {
        try record("search_notes(\(query), \(limit))")
        return hits
    }

    func readNote(path: String, maxBytes: Int) async throws -> ToolNote {
        try record("read_note(\(path), \(maxBytes))")
        return note
    }

    func openLoops(source: String?, project: String?, status: String?) async throws -> [ToolLoopRow] {
        try record("list_open_loops(\(source ?? "-"), \(project ?? "-"), \(status ?? "-"))")
        return rows
    }

    func listProjects() async -> ToolProjectInventory {
        lock.withLock { recorded.append("list_projects()") }
        return ToolProjectInventory(
            state: "populated",
            projects: [ToolProjectListing(slug: "alpha", title: "Alpha", path: "01-projects/alpha/hub.md")],
            truncated: false, reason: nil)
    }

    func project(slug: String) async throws -> ToolProject {
        try record("get_project(\(slug))")
        return ToolProject(
            slug: slug, title: "Alpha", hubPath: "01-projects/alpha/hub.md", summary: nil, decisions: [],
            checkouts: [], openLoops: rows, nativeTickets: [], nativeTicketsUnavailable: nil,
            relatedNotes: [], latestRestart: nil)
    }

    func agenda(day: LocalDay) async throws -> [ToolEvent] {
        try record("get_agenda(\(day))")
        return events
    }
}

/// Serves canned HTTP responses to `URLSession`s configured with it, and records the requests.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var headers: [String: String] = ["content-type": "text/event-stream"]
        var body = Data()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var reply = Reply()
    nonisolated(unsafe) private static var seen: [(request: URLRequest, body: Data)] = []

    static func serve(_ reply: Reply) {
        lock.withLock {
            self.reply = reply
            seen = []
        }
    }

    static var requests: [(request: URLRequest, body: Data)] { lock.withLock { seen } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        let reply = Self.lock.withLock {
            Self.seen.append((request, body))
            return Self.reply
        }
        let response = HTTPURLResponse(
            url: request.url ?? AnthropicClient.defaultEndpoint, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: reply.headers)
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

// Response builders.

func agentResponse(
    _ blocks: [AgentContentBlock], stop: String, category: String? = nil, model: String = "claude-opus-5-5"
) -> AgentResponse {
    AgentResponse(
        id: "msg_test", model: model, stopReason: stop,
        stopDetails: category.map { AgentStopDetails(category: $0, explanation: nil) }, content: blocks)
}

func toolCall(_ id: String, _ name: String, _ input: String) -> AgentContentBlock {
    .toolUse(id: id, name: name, inputJSON: Data(input.utf8))
}

extension Data {
    /// True when `needle` occurs in these bytes exactly.
    func containsBytes(_ needle: Data) -> Bool { range(of: needle) != nil }
}

extension AgentRequest {
    /// The request body parsed back into Foundation values.
    var parsedBody: [String: Any] { (try? JSONSerialization.jsonObject(with: body())) as? [String: Any] ?? [:] }
}

/// A day and zone the tests pin "now" to: Thursday 2026-11-12 09:30 in Chicago.
enum AssistantTestClock {
    static let zone = TimeZone(identifier: "America/Chicago") ?? .current
    static let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9, minute: 30)) ?? Date()
    }()

    static var configuration: AssistantSession.Configuration {
        var configuration = AssistantSession.Configuration()
        configuration.now = { now }
        configuration.timeZone = { zone }
        return configuration
    }
}
