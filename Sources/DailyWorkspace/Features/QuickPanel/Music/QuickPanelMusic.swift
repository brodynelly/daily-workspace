import AppKit
import Combine
import Foundation

/// Polls only while the panel is visible or an explicitly started shuffle queue is active.
/// Preview calls the JXA fixture (which never contacts Music) and rejects every playback action.
@MainActor
final class QuickPanelMusic: ObservableObject {
    @Published private(set) var library: QuickPanelMusicLibrary?
    @Published private(set) var status: QuickPanelMusicStatus?
    @Published private(set) var selectedPlaylistID: String?
    @Published private(set) var queue: QuickPanelMusicShuffleQueue?
    @Published private(set) var animationTrackID: String?
    @Published private(set) var errorMessage: String?

    let preview: Bool
    private let transport: any QuickPanelMusicTransport
    private let automaticPolling: Bool
    private let decoder = JSONDecoder()
    private var visible = false
    private var sleeping = false
    private var busy = false
    private var isPolling = false
    private var revision: UInt64 = 0
    private var pollingTask: Task<Void, Never>?
    nonisolated(unsafe) private var sleepObserver: NSObjectProtocol?
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?

    var selectedPlaylist: QuickPanelMusicPlaylist? {
        library?.playlists.first { $0.id == selectedPlaylistID }
    }

    var summary: String {
        if preview { return "Read-only layout preview · Music playback is disabled" }
        if let errorMessage { return errorMessage }
        guard let status else { return "Music status unavailable" }
        var text =
            "\(status.state)  ·  \(status.track?.name ?? "") — \(status.track?.artist ?? "")  ·  volume \(status.volume)%"
        if let track = status.track, track.duration > 0 {
            let position = Int(min(1_000_000_000, max(0, status.position)))
            let duration = Int(min(1_000_000_000, track.duration))
            text += " · \(position / 60):\(String(format: "%02d", position % 60))"
            text += " / \(duration / 60):\(String(format: "%02d", duration % 60))"
        }
        if let queue { text += "  ·  shuffled \(queue.progress)" }
        return text
    }

    init(
        transport: any QuickPanelMusicTransport = NativeQuickPanelMusicTransport(), preview: Bool = false,
        observesSleep: Bool = true, automaticPolling: Bool = true
    ) {
        self.transport = transport
        self.preview = preview
        self.automaticPolling = automaticPolling
        if observesSleep {
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.setSleeping(true) } }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.setSleeping(false) } }
        }
    }

    deinit {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        pollingTask?.cancel()
    }

    func selectPlaylist(_ id: String) {
        guard library?.playlists.contains(where: { $0.id == id }) == true else { return }
        selectedPlaylistID = id
    }

    func setVisible(_ visible: Bool) {
        guard self.visible != visible else { return }
        self.visible = visible
        if !visible {
            animationTrackID = nil
            revision &+= 1
        }
        reconcilePolling()
    }

    func setSleeping(_ sleeping: Bool) {
        guard self.sleeping != sleeping else { return }
        self.sleeping = sleeping
        if sleeping {
            animationTrackID = nil
            revision &+= 1
        }
        reconcilePolling()
    }

    func load() async throws {
        guard !busy else { throw QuickPanelMusicError.busy }
        busy = true
        stopPolling()
        defer {
            busy = false
            reconcilePolling()
        }
        do {
            try await refreshLibraryAndStatus()
            errorMessage = nil
        } catch {
            status = nil
            errorMessage = Self.describe(error)
            throw Self.map(error)
        }
    }

    func pollNow() async throws {
        guard !sleeping, !busy, !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        let capturedRevision = revision
        do {
            let latest: QuickPanelMusicStatus = try await call(preview ? ["fixture", "status"] : ["status"])
            guard revision == capturedRevision, !busy, !sleeping else { return }
            status = latest
            errorMessage = nil
            switch advanceDecision(for: latest) {
            case .none: break
            case .cancel:
                queue = nil
                reconcilePolling()
            case .advance:
                busy = true
                defer {
                    busy = false
                    reconcilePolling()
                }
                try await stepQueue(by: 1)
            }
        } catch {
            guard revision == capturedRevision, !busy, !sleeping else { return }
            if !(error is CancellationError) {
                status = nil
                errorMessage = Self.describe(error)
                throw Self.map(error)
            }
        }
    }

    private func refreshLibraryAndStatus() async throws {
        let capturedRevision = revision
        let nextLibrary: QuickPanelMusicLibrary = try await call(preview ? ["fixture", "library"] : ["library"])
        guard capturedRevision == revision, !sleeping else { return }
        library = nextLibrary
        if !nextLibrary.playlists.contains(where: { $0.id == selectedPlaylistID }) {
            selectedPlaylistID = nextLibrary.playlists.first?.id
        }
        let latest: QuickPanelMusicStatus = try await call(preview ? ["fixture", "status"] : ["status"])
        guard capturedRevision == revision, !sleeping else { return }
        status = latest
    }

    private func call<T: Decodable>(_ arguments: [String]) async throws -> T {
        do {
            let data = try await transport.call(arguments)
            guard data.count <= QuickPanelCommandRunner.defaultOutputLimit else {
                throw QuickPanelMusicError.invalidResponse
            }
            switch try decoder.decode(QuickPanelMusicBridgeResponse<T>.self, from: data) {
            case .value(let result): return result
            case .failure(let code):
                throw code == -1743 ? QuickPanelMusicError.permissionDenied : .failed
            }
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let music = error as? QuickPanelMusicError { return music }
        let nsError = error as NSError
        if nsError.code == -1743
            || error.localizedDescription.range(of: #"(?<![0-9])-?1743(?![0-9])"#, options: .regularExpression)
                != nil
        {
            return QuickPanelMusicError.permissionDenied
        }
        if error is DecodingError { return QuickPanelMusicError.invalidResponse }
        return QuickPanelMusicError.failed
    }

    private static func describe(_ error: Error) -> String {
        (map(error) as? QuickPanelMusicError)?.localizedDescription ?? QuickPanelMusicError.failed.localizedDescription
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        revision &+= 1
    }

    private func reconcilePolling() {
        guard automaticPolling, !sleeping, visible || queue != nil, !busy else {
            stopPolling()
            return
        }
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    do {
                        if self.library == nil {
                            try await self.refreshLibraryAndStatus()
                        } else {
                            try await self.pollNow()
                        }
                    } catch {
                        if !Task.isCancelled { self.errorMessage = Self.describe(error) }
                    }
                } else {
                    break
                }
                do { try await Task.sleep(nanoseconds: 900_000_000) } catch { break }
            }
        }
    }
}

private enum AdvanceDecision { case none, advance, cancel }

extension QuickPanelMusic {
    func perform(_ action: QuickPanelMusicAction, reduceMotion: Bool? = nil) async throws {
        guard !preview else { throw QuickPanelMusicError.readOnly }
        guard !busy else { throw QuickPanelMusicError.busy }
        busy = true
        stopPolling()
        defer {
            busy = false
            animationTrackID = nil
            reconcilePolling()
        }
        do {
            try await performAction(action, reduceMotion: reduceMotion)
            errorMessage = nil
        } catch {
            if !(error is CancellationError) { errorMessage = Self.describe(error) }
            throw Self.map(error)
        }
    }

    private func performAction(_ action: QuickPanelMusicAction, reduceMotion: Bool?) async throws {
        switch action {
        case .play(let playlistID, let trackID):
            queue = nil
            status = try await call(["play", playlistID, trackID])
        case .playPause:
            status = try await call(["playpause"])
        case .pause:
            status = try await call(["pause"])
        case .stop:
            queue = nil
            status = try await call(["stop"])
        case .next:
            try await stepOrCall(by: 1, command: "next")
        case .previous:
            try await stepOrCall(by: -1, command: "prev")
        case .volume(let delta):
            status = try await call(["volume", String(min(100, max(-100, delta)))])
        case .endShuffle:
            queue = nil
        case .shuffle(let filtered, let first, let single):
            try await startShuffle(filtered: filtered, first: first, single: single, reduceMotion: reduceMotion)
        }
    }

    private func stepOrCall(by delta: Int, command: String) async throws {
        if queue == nil { status = try await call([command]) } else { try await stepQueue(by: delta) }
    }

    private func startShuffle(filtered: [String]?, first: String?, single: Bool, reduceMotion: Bool?) async throws {
        guard let playlist = selectedPlaylist else { throw QuickPanelMusicError.emptyPlaylist }
        let allowed = filtered.map { Set($0) }
        let ids = playlist.tracks.compactMap { track -> String? in
            guard let allowed else { return track.id }
            return allowed.contains(track.id) ? track.id : nil
        }
        guard
            let proposed = QuickPanelMusicShuffleQueue(
                playlistID: playlist.id, trackIDs: ids, firstTrackID: first
            )
        else { throw QuickPanelMusicError.emptyPlaylist }
        let animate = visible && !(reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let capturedRevision = revision
        if animate {
            for index in 0..<min(8, ids.count * 2) {
                animationTrackID = proposed.tracks[index % proposed.tracks.count]
                try await Task.sleep(nanoseconds: 70_000_000)
                guard capturedRevision == revision, visible, !sleeping else { throw CancellationError() }
            }
        }
        animationTrackID = nil
        if single {
            queue = nil
            status = try await call(["play", proposed.playlistID, proposed.currentTrackID])
        } else {
            queue = proposed
            do { try await playQueued() } catch {
                queue = nil
                throw error
            }
        }
    }

    private func advanceDecision(for latest: QuickPanelMusicStatus) -> AdvanceDecision {
        guard var queue else { return .none }
        if latest.track?.id == queue.currentTrackID {
            queue.started = true
            let remaining = (latest.track?.duration ?? 0) - latest.position
            queue.lastRemaining = remaining
            self.queue = queue
            if latest.state == "playing", queue.index + 1 < queue.tracks.count,
                (latest.track?.duration ?? 0) > 0, remaining <= 1.5
            {
                return .advance
            }
            return .none
        }
        guard queue.started else { return latest.state == "stopped" ? .cancel : .none }
        return (queue.lastRemaining ?? .infinity) <= 4 ? .advance : .cancel
    }

    private func playQueued() async throws {
        guard var queue else { return }
        queue.started = false
        queue.lastRemaining = nil
        self.queue = queue
        status = try await call(["play", queue.playlistID, queue.currentTrackID])
    }

    private func stepQueue(by delta: Int) async throws {
        guard var queue else { return }
        let next = max(0, queue.index + delta)
        if next >= queue.tracks.count {
            self.queue = nil
            status = try await call(["stop"])
        } else {
            queue.index = next
            self.queue = queue
            try await playQueued()
        }
    }
}
