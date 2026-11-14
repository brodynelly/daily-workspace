import Foundation
import XCTest

@testable import DailyWorkspace

private actor FakeMusicBridge: QuickPanelMusicTransport {
    private(set) var calls: [[String]] = []
    private var pendingStatuses: [Data] = []
    private var currentTrackID: String?
    var failure: Error?
    var bridgeError: Data?

    func enqueueStatus(_ status: Data) { pendingStatuses.append(status) }
    func setBridgeError(_ error: Data?) { bridgeError = error }
    func setFailure(_ error: Error?) { failure = error }

    func call(_ arguments: [String]) async throws -> Data {
        calls.append(arguments)
        if let failure { throw failure }
        if let bridgeError { return bridgeError }
        switch arguments.first {
        case "library", "fixture":
            if arguments == ["fixture", "status"] { return try Self.player(id: nil, state: "stopped") }
            return Data(
                #"{"playlists":[{"id":"list","name":"Library","tracks":[["a","First","Artist","Album",100],["b","Second","Artist","Album",100],["c","Third","Artist","Album",100]]}]}"#
                    .utf8)
        case "status":
            if !pendingStatuses.isEmpty { return pendingStatuses.removeFirst() }
            return try Self.player(id: currentTrackID, state: currentTrackID == nil ? "stopped" : "playing")
        case "play":
            currentTrackID = arguments[2]
            return try Self.player(id: currentTrackID)
        case "stop":
            currentTrackID = nil
            return try Self.player(id: nil, state: "stopped")
        case "playpause", "pause", "next", "prev", "volume":
            return try Self.player(id: currentTrackID)
        default:
            XCTFail("Unexpected Music request: \(arguments)")
            return Data()
        }
    }

    static func player(id: String?, position: Double = 0, state: String = "playing") throws -> Data {
        let track: Any =
            id.map { ["id": $0, "name": "Song", "artist": "Artist", "album": "Album", "duration": 100] as Any }
            ?? NSNull()
        return try JSONSerialization.data(withJSONObject: [
            "state": state, "volume": 50, "track": track, "position": position,
        ])
    }
}

private struct SeededMusicRandom: RandomNumberGenerator {
    var state: UInt64
    private(set) var calls = 0

    mutating func next() -> UInt64 {
        calls += 1
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@MainActor
final class QuickPanelMusicTests: XCTestCase {
    private func music(_ bridge: FakeMusicBridge, preview: Bool = false, automaticPolling: Bool = false)
        -> QuickPanelMusic
    {
        QuickPanelMusic(transport: bridge, preview: preview, observesSleep: false, automaticPolling: automaticPolling)
    }

    func testLoadAndReadOnlyPollingNeverWriteToMusic() async throws {
        let bridge = FakeMusicBridge()
        let music = music(bridge)
        try await music.load()
        try await music.pollNow()

        XCTAssertEqual(music.selectedPlaylistID, "list")
        XCTAssertEqual(music.selectedPlaylist?.tracks.map(\.timeLabel), ["1:40", "1:40", "1:40"])
        let calls = await bridge.calls
        XCTAssertEqual(calls, [["library"], ["status"], ["status"]])
    }

    func testShuffleAdvancesBeforeEndAndStopsAfterLastNaturalTransition() async throws {
        let bridge = FakeMusicBridge()
        let music = music(bridge)
        try await music.load()
        try await music.perform(.shuffle(filteredTrackIDs: ["a", "b"], firstTrackID: "a"), reduceMotion: true)
        XCTAssertEqual(music.queue?.currentTrackID, "a")
        XCTAssertEqual(music.queue?.tracks.sorted(), ["a", "b"])
        XCTAssertEqual(music.queue?.progress, "1/2")

        await bridge.enqueueStatus(try FakeMusicBridge.player(id: "a", position: 99))
        try await music.pollNow()
        XCTAssertEqual(music.queue?.currentTrackID, "b")
        XCTAssertEqual(music.queue?.progress, "2/2")

        await bridge.enqueueStatus(try FakeMusicBridge.player(id: "b", position: 98))
        try await music.pollNow()
        await bridge.enqueueStatus(try FakeMusicBridge.player(id: "outside", position: 0))
        try await music.pollNow()
        XCTAssertNil(music.queue)
        let calls = await bridge.calls
        XCTAssertEqual(
            Array(calls.suffix(6)),
            [
                ["play", "list", "a"], ["status"], ["play", "list", "b"],
                ["status"], ["status"], ["stop"],
            ])
    }

    func testNaturalTransitionNearEndAdvancesButExternalChangeCancels() async throws {
        let bridge = FakeMusicBridge()
        let music = music(bridge)
        try await music.load()
        try await music.perform(.shuffle(filteredTrackIDs: ["a", "b"], firstTrackID: "a"), reduceMotion: true)
        await bridge.enqueueStatus(try FakeMusicBridge.player(id: "a", position: 97))
        try await music.pollNow()
        await bridge.enqueueStatus(try FakeMusicBridge.player(id: "another", position: 0))
        try await music.pollNow()
        XCTAssertEqual(music.queue?.currentTrackID, "b")

        await bridge.enqueueStatus(try FakeMusicBridge.player(id: "b", position: 50))
        try await music.pollNow()
        await bridge.enqueueStatus(try FakeMusicBridge.player(id: "outside", position: 0))
        try await music.pollNow()
        XCTAssertNil(music.queue)
        let calls = await bridge.calls
        XCTAssertEqual(
            calls.filter { $0.first == "play" },
            [
                ["play", "list", "a"], ["play", "list", "b"],
            ])
        XCTAssertFalse(calls.contains(["stop"]))
    }

    func testQueueNextPreviousAndEndShuffle() async throws {
        let bridge = FakeMusicBridge()
        let music = music(bridge)
        try await music.load()
        try await music.perform(.shuffle(filteredTrackIDs: ["a", "b"], firstTrackID: "a"), reduceMotion: true)
        try await music.perform(.previous)
        XCTAssertEqual(music.queue?.progress, "1/2")
        try await music.perform(.next)
        XCTAssertEqual(music.queue?.progress, "2/2")
        try await music.perform(.next)
        XCTAssertNil(music.queue)
        let calls = await bridge.calls
        XCTAssertEqual(
            Array(calls.suffix(4)),
            [
                ["play", "list", "a"], ["play", "list", "a"], ["play", "list", "b"], ["stop"],
            ])
    }

    func testShuffleUsesFreshEntropyAndPreservesSelectedFirstTrack() async throws {
        let ids = ["a", "b", "c", "d", "e", "f"]
        var low = SeededMusicRandom(state: 0)
        var high = SeededMusicRandom(state: 42)
        let first = try XCTUnwrap(
            QuickPanelMusicShuffleQueue(playlistID: "list", trackIDs: ids, firstTrackID: "a", using: &low))
        let second = try XCTUnwrap(
            QuickPanelMusicShuffleQueue(playlistID: "list", trackIDs: ids, firstTrackID: "a", using: &high))
        XCTAssertGreaterThan(low.calls, 0)
        XCTAssertGreaterThan(high.calls, 0)
        XCTAssertEqual(first.tracks.first, "a")
        XCTAssertEqual(second.tracks.first, "a")
        XCTAssertEqual(first.tracks.sorted(), ids)
        XCTAssertEqual(second.tracks.sorted(), ids)
        XCTAssertNotEqual(first.tracks, second.tracks)

        let bridge = FakeMusicBridge()
        let music = music(bridge)
        try await music.load()
        try await music.perform(
            .shuffle(filteredTrackIDs: ["a", "b"], firstTrackID: "b", single: true), reduceMotion: true)
        XCTAssertNil(music.queue)
        let calls = await bridge.calls
        XCTAssertEqual(calls.last, ["play", "list", "b"])
    }

    func testPlaybackAndVolumeUseOnlyExplicitFixedArguments() async throws {
        let bridge = FakeMusicBridge()
        let music = music(bridge)
        try await music.load()
        try await music.perform(.play(playlistID: "list", trackID: "a"))
        try await music.perform(.playPause)
        try await music.perform(.pause)
        try await music.perform(.next)
        try await music.perform(.previous)
        try await music.perform(.volume(10_000))
        try await music.perform(.volume(-10_000))
        try await music.perform(.stop)
        let calls = await bridge.calls
        XCTAssertEqual(
            Array(calls.dropFirst(2)),
            [
                ["play", "list", "a"], ["playpause"], ["pause"], ["next"], ["prev"],
                ["volume", "100"], ["volume", "-100"], ["stop"],
            ])
    }

    func testPreviewFixtureReadsWithoutAutomationAndBlocksPlayback() async throws {
        let bridge = FakeMusicBridge()
        let music = music(bridge, preview: true)
        try await music.load()
        XCTAssertEqual(music.library?.playlists.first?.name, "Library")
        XCTAssertTrue(music.summary.lowercased().contains("read-only"))
        let actions: [QuickPanelMusicAction] = [.playPause, .shuffle(), .volume(10), .stop, .endShuffle]
        for action in actions {
            do {
                try await music.perform(action)
                XCTFail("Preview should reject playback")
            } catch {
                XCTAssertEqual(error as? QuickPanelMusicError, .readOnly)
            }
        }
        let calls = await bridge.calls
        XCTAssertEqual(calls, [["fixture", "library"], ["fixture", "status"]])
    }

    func testAutomation1743HasActionableExplanation() async {
        let bridge = FakeMusicBridge()
        await bridge.setBridgeError(Data(#"{"error":{"code":-1743}}"#.utf8))
        let music = music(bridge)
        do {
            try await music.load()
            XCTFail("Expected denied Automation access")
        } catch {
            XCTAssertEqual(error as? QuickPanelMusicError, .permissionDenied)
            XCTAssertTrue(music.errorMessage?.contains("Privacy & Security → Automation") == true)
        }
        let calls = await bridge.calls
        XCTAssertEqual(calls, [["library"]])
    }

    func testPollingFailureAfterLoadShowsPermissionInsteadOfStalePlayback() async throws {
        let bridge = FakeMusicBridge()
        await bridge.enqueueStatus(try FakeMusicBridge.player(id: "a"))
        let music = music(bridge)
        try await music.load()
        XCTAssertNotNil(music.library)
        XCTAssertNotNil(music.status)
        XCTAssertTrue(music.summary.contains("Song"))

        await bridge.setBridgeError(Data(#"{"error":{"code":-1743}}"#.utf8))
        do {
            try await music.pollNow()
            XCTFail("Expected denied Automation access")
        } catch {
            XCTAssertEqual(error as? QuickPanelMusicError, .permissionDenied)
        }
        XCTAssertNil(music.status)
        XCTAssertTrue(music.summary.contains("Privacy & Security → Automation"))
        XCTAssertFalse(music.summary.contains("Song"))

        await bridge.setBridgeError(nil)
        try await music.pollNow()
        XCTAssertNil(music.errorMessage)
        XCTAssertNotNil(music.status)
    }

    func testAutomationMessageOnly1743DoesNotMisclassifyUnrelatedCodes() async {
        let bridge = FakeMusicBridge()
        let music = music(bridge)
        await bridge.setFailure(
            NSError(
                domain: "JXA", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not authorized to send Apple events (-1743)"]))
        do {
            try await music.load()
            XCTFail("Expected denied Automation access")
        } catch {
            XCTAssertEqual(error as? QuickPanelMusicError, .permissionDenied)
        }
        await bridge.setFailure(
            NSError(
                domain: "JXA", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Music request 11743 failed"]))
        do {
            try await music.load()
            XCTFail("Expected Music failure")
        } catch {
            XCTAssertEqual(error as? QuickPanelMusicError, .failed)
        }
    }

    func testAnimationAndReduceMotionFallback() async throws {
        let bridge = FakeMusicBridge()
        let music = music(bridge)
        try await music.load()
        music.setVisible(true)
        let animated = Task {
            try await music.perform(.shuffle(filteredTrackIDs: ["a", "b"], firstTrackID: "b"), reduceMotion: false)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(music.animationTrackID)
        try await animated.value
        XCTAssertNil(music.animationTrackID)
        try await music.perform(.shuffle(filteredTrackIDs: ["a", "b"], firstTrackID: "a"), reduceMotion: true)
        XCTAssertNil(music.animationTrackID)
        XCTAssertEqual(music.queue?.currentTrackID, "a")
        music.setVisible(false)
    }

    func testHideStopsIdlePollingAndSleepStopsActiveQueuePolling() async throws {
        let bridge = FakeMusicBridge()
        let music = music(bridge, automaticPolling: true)
        try await music.load()
        music.setVisible(true)
        try await Task.sleep(nanoseconds: 50_000_000)
        music.setVisible(false)
        let afterHide = await bridge.calls.count
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let hiddenCalls = await bridge.calls.count
        XCTAssertEqual(hiddenCalls, afterHide)

        try await music.perform(.shuffle(filteredTrackIDs: ["a", "b"], firstTrackID: "a"), reduceMotion: true)
        let beforeQueuePoll = await bridge.calls.count
        try await Task.sleep(nanoseconds: 50_000_000)
        let activeCalls = await bridge.calls.count
        XCTAssertGreaterThan(activeCalls, beforeQueuePoll)
        music.setSleeping(true)
        let afterSleep = await bridge.calls.count
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let sleepingCalls = await bridge.calls.count
        XCTAssertEqual(sleepingCalls, afterSleep)
    }
}
