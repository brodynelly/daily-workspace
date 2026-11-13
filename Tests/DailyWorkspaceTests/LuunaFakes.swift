import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

/// Real-shaped Luuna responses, from the runtime's handlers and the TypeScript client's types.
enum LuunaFixtures {
    static let health = Data(
        """
        {"status":"ok","pi_version":"0.66.1","pi_version_status":"required; checked on every run",
         "native_execution":true,"build_identity":"sha256:5d0c","build_rustc":"rustc 1.91.0",
         "build_rustc_sha256":"8e1f","build_rustc_wrapper":"none","build_flags":"profile=release"}
        """.utf8)

    static let projects = Data(
        """
        [{"id":"daily-workspace","name":"Daily Workspace","revision":3,"manifest_hash":"sha256:ab12",
          "created_at":"2026-11-02T09:14:03.512Z","updated_at":"2026-11-12T18:50:20.997716Z"}]
        """.utf8)

    static let project = Data(
        """
        {"project":{"id":"daily-workspace","name":"Daily Workspace","revision":3,"manifest_hash":null,
                    "created_at":"2026-11-02T09:14:03Z","updated_at":"2026-11-12T18:50:20Z"},
         "repositories":[],"manifest":null,"discovery":null}
        """.utf8)

    static let components = Data(
        """
        {"enabled":false,"workspace_path":"/tmp/luuna-fixture/projects/daily-workspace",
         "reason":"Component toolchain unavailable; configure a verified native component manifest and restart",
         "adapters":[]}
        """.utf8)

    static let healthValue: LuunaHealth = decode(health)
    static let projectsValue: [LuunaProjectRecord] = decode(projects)
    static let projectValue: LuunaProjectView = decode(project)
    static let componentsValue: LuunaComponentStatus = decode(components)

    private static func decode<Value: Decodable>(_ data: Data) -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            preconditionFailure("Luuna fixture does not decode: \(error)")
        }
    }
}

/// Lets a test hold a read in flight until it says so.
final class LuunaGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var arrived = false

    var hasArrived: Bool { lock.withLock { arrived } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                arrived = true
                if opened { return true }
                waiter = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let continuation = lock.withLock {
            opened = true
            defer { waiter = nil }
            return waiter
        }
        continuation?.resume()
    }

    /// Waits (up to two seconds) until a read is held at the gate.
    func waitForArrival(file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 where !hasArrived {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(hasArrived, "No read reached the gate", file: file, line: line)
    }
}

/// A scripted `LuunaRuntimeReading`. Thread-safe: the store runs project detail and component reads concurrently.
final class FakeLuunaReader: LuunaRuntimeReading, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [String: Result<Any, LuunaReadFailure>] = [
        "health": .success(LuunaFixtures.healthValue),
        "projects": .success(LuunaFixtures.projectsValue),
        "project": .success(LuunaFixtures.projectValue),
        "components": .success(LuunaFixtures.componentsValue),
    ]
    private var gates: [String: LuunaGate] = [:]
    private var log: [(call: String, connection: LuunaConnection)] = []

    var calls: [String] { lock.withLock { log.map(\.call) } }
    var connections: [LuunaConnection] { lock.withLock { log.map(\.connection) } }

    func set<Value>(_ call: String, _ result: Result<Value, LuunaReadFailure>) {
        lock.withLock { results[call] = result.map { $0 as Any } }
    }

    func hold(_ call: String) -> LuunaGate {
        let gate = LuunaGate()
        lock.withLock { gates[call] = gate }
        return gate
    }

    func health(_ connection: LuunaConnection) async throws -> LuunaHealth {
        try await answer("health", connection)
    }

    func projects(_ connection: LuunaConnection) async throws -> [LuunaProjectRecord] {
        try await answer("projects", connection)
    }

    func project(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaProjectView {
        try await answer("project", connection)
    }

    func components(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaComponentStatus {
        try await answer("components", connection)
    }

    private func answer<Value>(_ call: String, _ connection: LuunaConnection) async throws -> Value {
        let gate = lock.withLock {
            log.append((call, connection))
            return gates[call]
        }
        await gate?.wait()
        let result = lock.withLock { results[call] }
        switch result {
        case .success(let value as Value): return value
        case .failure(let failure): throw failure
        default: throw LuunaReadFailure.undecodable
        }
    }
}

extension LuunaConnection {
    static let fixture = LuunaConnection(origin: .standard, token: "test-token-not-a-secret")
}
