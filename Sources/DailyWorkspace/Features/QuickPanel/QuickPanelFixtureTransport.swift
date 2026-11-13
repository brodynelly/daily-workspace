import Foundation

/// Preview only: reads the configured fixture, never talks to or controls Music.
struct QuickPanelFixtureTransport: QuickPanelMusicTransport {
    let file: URL

    func call(_ arguments: [String]) async throws -> Data {
        guard arguments.first == "fixture" else { throw QuickPanelMusicError.readOnly }
        switch arguments.dropFirst().first {
        case "library":
            return try await Task.detached(priority: .utility) {
                let handle = try FileHandle(forReadingFrom: self.file)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: QuickPanelCommandRunner.defaultOutputLimit + 1) ?? Data()
                guard data.count <= QuickPanelCommandRunner.defaultOutputLimit,
                    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    object["playlists"] is [Any]
                else { throw QuickPanelMusicError.invalidResponse }
                return data
            }.value
        case "status":
            return Data(#"{"state":"stopped","volume":50,"track":null,"position":0}"#.utf8)
        default:
            throw QuickPanelMusicError.readOnly
        }
    }
}
