import Foundation

struct QuickPanelMusicTrack: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let duration: Int

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        id = try values.decode(String.self)
        name = try values.decode(String.self)
        artist = try values.decode(String.self)
        album = try values.decode(String.self)
        duration = try values.decode(Int.self)
    }

    var timeLabel: String { "\(duration / 60):\(String(format: "%02d", duration % 60))" }
}

struct QuickPanelMusicPlaylist: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let tracks: [QuickPanelMusicTrack]
}

struct QuickPanelMusicLibrary: Decodable, Equatable {
    let playlists: [QuickPanelMusicPlaylist]
}

struct QuickPanelMusicStatus: Decodable, Equatable {
    struct Track: Decodable, Equatable {
        let id: String
        let name: String
        let artist: String
        let album: String
        let duration: Double
    }

    let state: String
    let volume: Int
    let track: Track?
    let position: Double
}

enum QuickPanelMusicAction {
    case play(playlistID: String, trackID: String)
    case playPause
    case pause
    case stop
    case next
    case previous
    case volume(Int)
    case shuffle(filteredTrackIDs: [String]? = nil, firstTrackID: String? = nil, single: Bool = false)
    case endShuffle
}

enum QuickPanelMusicError: LocalizedError, Equatable {
    case permissionDenied
    case readOnly
    case missingScript
    case invalidResponse
    case emptyPlaylist
    case busy
    case failed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Allow Daily Workspace to control Music in System Settings → Privacy & Security → Automation."
        case .readOnly:
            "Music preview is read-only. Open normal Music to control playback."
        case .missingScript:
            "The Music bridge is missing from the app resources."
        case .invalidResponse:
            "Music returned an invalid response."
        case .emptyPlaylist:
            "This playlist has no playable tracks."
        case .busy:
            "Music is finishing another action."
        case .failed:
            "Could not communicate with Music."
        }
    }
}

/// The production adapter uses only a fixed executable and positional arguments; tests inject a fake.
protocol QuickPanelMusicTransport: Sendable {
    func call(_ arguments: [String]) async throws -> Data
}

struct NativeQuickPanelMusicTransport: QuickPanelMusicTransport {
    private let script: URL?
    private let runner = QuickPanelCommandRunner(timeout: 45)

    init() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let executableDirectory = executable.deletingLastPathComponent()
        var candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("music.js"),
            executableDirectory.appendingPathComponent("../Resources/music.js"),
        ]
        // `swift run` has no .app Resources. Search the workspace beside its build directory,
        // as well as the current directory when launched from the checkout.
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/music.js"))
        var ancestor = executableDirectory
        for _ in 0..<4 {
            ancestor.deleteLastPathComponent()
            candidates.append(ancestor.appendingPathComponent("Resources/music.js"))
        }
        script = candidates.compactMap { $0?.standardizedFileURL }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    func call(_ arguments: [String]) async throws -> Data {
        guard let script else { throw QuickPanelMusicError.missingScript }
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-l", "JavaScript", script.path] + arguments
        )
        return output.stdout
    }
}

struct QuickPanelMusicShuffleQueue: Equatable {
    let playlistID: String
    let tracks: [String]
    var index = 0
    var started = false
    var lastRemaining: Double?

    var currentTrackID: String { tracks[index] }
    var progress: String { "\(index + 1)/\(tracks.count)" }

    init?(playlistID: String, trackIDs: [String], firstTrackID: String? = nil) {
        var generator = SystemRandomNumberGenerator()
        self.init(playlistID: playlistID, trackIDs: trackIDs, firstTrackID: firstTrackID, using: &generator)
    }

    init?<R: RandomNumberGenerator>(
        playlistID: String, trackIDs: [String], firstTrackID: String? = nil, using generator: inout R
    ) {
        guard !trackIDs.isEmpty else { return nil }
        self.playlistID = playlistID
        var shuffled = trackIDs
        shuffled.shuffle(using: &generator)
        if let firstTrackID, let index = shuffled.firstIndex(of: firstTrackID) {
            shuffled.swapAt(0, index)
        }
        tracks = shuffled
    }
}

/// The JXA bridge returns either a Music value or an Automation error code.
enum QuickPanelMusicBridgeResponse<T: Decodable>: Decodable {
    case value(T)
    case failure(Int)

    private enum Keys: String, CodingKey { case error }
    private struct Failure: Decodable { let code: Int }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if container.contains(.error) {
            self = .failure(try container.decode(Failure.self, forKey: .error).code)
        } else {
            self = .value(try T(from: decoder))
        }
    }
}
