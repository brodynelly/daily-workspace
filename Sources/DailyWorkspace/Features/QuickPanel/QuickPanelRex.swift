import AppKit
import Foundation

/// Rex sessions for the tmux sessionizer. Rex is a native multiplexer with its own server, so it is a
/// separate source from tmux. Every call passes `--autostart=false`: listing must never start a server.
enum QuickPanelRex {
    static let bundleID = "com.superlogical.rex"
    static let group = "Rex"
    /// `rex` exits 4 when no server is running and autostart is disabled.
    static let serverNotRunningStatus: Int32 = 4

    /// `rex` is on PATH only inside Rex terminals, so resolve the binary that matches the installed server.
    static func locate(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let candidates = [
            home.appendingPathComponent(
                "Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/"
                    + "Rex Server.app/Contents/MacOS/rex"),
            URL(fileURLWithPath: "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"),
            URL(fileURLWithPath: "/Applications/Rex.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static let listArguments = ["--autostart=false", "--timeout", "5s", "ls", "--json"]

    static func selectArguments(sessionID: String) -> [String] {
        ["--autostart=false", "--timeout", "5s", "do", "session.select", "session_id=\(sessionID)"]
    }

    static func validSessionID(_ value: String) -> Bool {
        guard value.hasPrefix("session:") else { return false }
        let rest = value.dropFirst("session:".count)
        return !rest.isEmpty && rest.utf8.count <= 64
            && rest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) || $0 == 45 }
    }

    /// Parses `rex ls --json`; `nil` means the response was not the documented shape.
    static func parseSessions(_ data: Data) -> [QuickPanelDataRow]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let sessions = object["sessions"] as? [Any]
        else { return nil }
        return sessions.compactMap { value -> QuickPanelDataRow? in
            guard let session = value as? [String: Any], let id = nonempty(session, "session_id"),
                validSessionID(id)
            else { return nil }
            let shortID = String(id.suffix(6))
            let label = nonempty(session, "label").flatMap { label in
                label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) ? nil : label
            }
            var row = QuickPanelDataRow(
                id: "rex:\(id)", title: label ?? shortID, detail: "rex · \(shortID)", group: group,
                action: .focusRexSession(id))
            row.badge = "rex"
            row.keywords = "rex"
            return row
        }
    }

    static func rows(executable: URL?, output: Result<QuickPanelCommandOutput, Error>?) -> [QuickPanelDataRow] {
        guard executable != nil, let output else { return [.unavailable(group, "Rex is not installed")] }
        switch output {
        case .success(let result) where result.exitStatus == serverNotRunningStatus:
            return [.unavailable(group, "Rex server is not running")]
        case .success(let result) where result.exitStatus == 0:
            return parseSessions(result.stdout) ?? [.unavailable(group, "Invalid Rex sessions response")]
        default:
            return [.unavailable(group, "Rex sessions could not be listed")]
        }
    }

    /// `session.select` changes the session inside Rex's window; bring the app forward as well.
    @MainActor
    static func activateApp() {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open(url)
        }
    }
}
