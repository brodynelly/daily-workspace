import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

private actor ScriptedFollow: LuunaRunFollowing {
    enum Scenario { case reconnect, foreign, selectionSwitch, oversizedList, largeBatches, malformed, idleAfterStart }
    let scenario: Scenario
    private var attempts: [Int] = []

    init(_ scenario: Scenario) { self.scenario = scenario }
    var afters: [Int] { attempts }

    func follow(
        _ runID: String, after sequence: Int, _ connection: LuunaConnection,
        onChunk: @escaping @Sendable (Data) -> Void
    ) async throws {
        attempts.append(sequence)
        switch scenario {
        case .reconnect:
            try reconnect(runID, after: sequence, onChunk: onChunk)
        case .foreign:
            onChunk(Self.event(1, "different-run"))
        case .selectionSwitch:
            onChunk(Self.event(1, runID))
            if runID == "old" { try await Task.sleep(for: .seconds(30)) }
        case .oversizedList:
            onChunk(Data((1...600).flatMap { Self.event($0, runID) }))
        case .largeBatches:
            let payload = String(repeating: "x", count: 600_000)
            for number in 1...5 {
                onChunk(
                    Data(
                        "{\"sequence\":\(number),\"run_id\":\"\(runID)\",\"project_id\":\"p\",\"payload\":{\"chunk\":\"\(payload)\"}}\n"
                            .utf8))
            }
        case .malformed:
            onChunk(Data("not NDJSON\n".utf8))
            throw LuunaReadFailure.unavailable(.timedOut)
        case .idleAfterStart:
            try idle(runID, after: sequence, onChunk: onChunk)
        }
    }

    private func reconnect(
        _ runID: String, after sequence: Int, onChunk: @Sendable (Data) -> Void
    ) throws {
        if sequence == 0 {
            let first = Self.event(1, runID)
            onChunk(Data(first.prefix(19)))
            onChunk(Data(first.dropFirst(19)))
            throw LuunaReadFailure.unavailable(.cannotConnect)
        }
        onChunk(Self.event(1, runID) + Self.event(2, runID))
    }

    private func idle(
        _ runID: String, after sequence: Int, onChunk: @Sendable (Data) -> Void
    ) throws {
        if sequence == 0 {
            onChunk(Self.event(1, runID))
            throw LuunaReadFailure.unavailable(.timedOut)
        }
        if attempts.count < 6 { throw LuunaReadFailure.unavailable(.timedOut) }
        onChunk(Self.event(2, runID))
    }

    private static func event(_ sequence: Int, _ runID: String) -> Data {
        Data(
            "{\"sequence\":\(sequence),\"run_id\":\"\(runID)\",\"project_id\":\"p\",\"type\":\"check.output\",\"payload\":{\"chunk\":\"text\"}}\n"
                .utf8)
    }
}

@MainActor
final class LuunaRunFollowerTests: XCTestCase {
    func testReconnectUsesLastCompleteSequenceAndDeduplicatesReplay() async throws {
        let reader = ScriptedFollow(.reconnect)
        let follower = LuunaRunFollower(reader: reader)
        follower.start(runID: "run-1", projectID: "p", connection: .fixture)
        try await waitUntil { !follower.isFollowing }
        let attempts = await reader.afters
        XCTAssertEqual(attempts, [0, 1])
        XCTAssertEqual(follower.cursor, 2)
        XCTAssertEqual(follower.events.value?.map(\.sequence), [1, 2])
        XCTAssertEqual(follower.events.state, .populated)
    }

    func testForeignRunIsRefusedWithoutPublishingItsPayload() async throws {
        let follower = LuunaRunFollower(reader: ScriptedFollow(.foreign))
        follower.start(runID: "run-1", projectID: "p", connection: .fixture)
        try await waitUntil { !follower.isFollowing }
        XCTAssertNil(follower.events.value)
        XCTAssertEqual(follower.events.state, .partial)
    }

    func testSwitchDiscardsOldRunAndCancelsItsFollow() async throws {
        let reader = ScriptedFollow(.selectionSwitch)
        let follower = LuunaRunFollower(reader: reader)
        follower.start(runID: "old", projectID: "p", connection: .fixture)
        try await waitUntil { follower.events.value?.first?.fields["run_id"]?.stringValue == "old" }
        follower.start(runID: "new", projectID: "p", connection: .fixture)
        try await waitUntil { !follower.isFollowing }
        XCTAssertEqual(follower.events.value?.map { $0.fields["run_id"]?.stringValue }, ["new"])
        XCTAssertEqual(follower.cursor, 1)
    }

    func testLongFollowKeepsOnlyRecentEvents() async throws {
        let follower = LuunaRunFollower(reader: ScriptedFollow(.oversizedList))
        follower.start(runID: "r", projectID: "p", connection: .fixture)
        try await waitUntil { !follower.isFollowing }
        XCTAssertEqual(follower.events.value?.first?.sequence, 101)
        XCTAssertEqual(follower.events.value?.last?.sequence, 600)
        XCTAssertEqual(follower.cursor, 600)
    }

    func testRetainedEventBytesAreBoundedAcrossChunkBatches() async throws {
        let follower = LuunaRunFollower(reader: ScriptedFollow(.largeBatches))
        follower.start(runID: "r", projectID: "p", connection: .fixture)
        try await waitUntil { !follower.isFollowing }
        XCTAssertEqual(follower.events.value?.map(\.sequence), [3, 4, 5])
        XCTAssertEqual(follower.cursor, 5)
    }

    func testMalformedStreamRemainsPartialInsteadOfBecomingUnavailable() async throws {
        let reader = ScriptedFollow(.malformed)
        let follower = LuunaRunFollower(reader: reader)
        follower.start(runID: "r", projectID: "p", connection: .fixture)
        try await waitUntil { !follower.isFollowing }
        XCTAssertEqual(follower.events.state, .partial)
        let attempts = await reader.afters
        XCTAssertEqual(attempts, [0])
    }

    func testChangingCredentialClearsSelectedRunEventsAndStopsOldStream() async throws {
        let follower = LuunaRunFollower(reader: ScriptedFollow(.selectionSwitch))
        let store = LuunaWorkStore(follower: follower)
        store.connect(origin: .standard, token: "first", projectID: "p")
        store.selectRun("old")
        store.followSelectedRun()
        try await waitUntil { follower.events.value?.first?.fields["run_id"]?.stringValue == "old" }
        store.connect(origin: .standard, token: "second", projectID: "p")
        XCTAssertFalse(follower.isFollowing)
        XCTAssertNil(follower.events.value)
        XCTAssertEqual(follower.events.state, .unavailable(.notChecked))
        XCTAssertNil(store.selectedRunID)
    }

    func testActiveRunSurvivesIdleReconnectsAfterFirstEvent() async throws {
        let reader = ScriptedFollow(.idleAfterStart)
        let follower = LuunaRunFollower(reader: reader)
        follower.start(runID: "r", projectID: "p", connection: .fixture)
        try await waitUntil { !follower.isFollowing }
        XCTAssertEqual(follower.events.value?.map(\.sequence), [1, 2])
        XCTAssertEqual(follower.cursor, 2)
        let attempts = await reader.afters
        XCTAssertEqual(attempts, [0, 1, 1, 1, 1, 1])
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Read-only follow did not settle within four seconds")
    }
}
