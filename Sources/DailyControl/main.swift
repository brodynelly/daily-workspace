import AppKit
import Darwin
import Foundation

private enum ControlFailure: Error, LocalizedError {
    case usage, unavailable, unsafePath, oversizedResponse, invalidResponse, server(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: daily [--config path] show|toggle <view> | hide | status | inspect | attention-refresh | palette-reload | clipboard | mouse center|corner"
        case .unavailable: "Daily Workspace control service is unavailable."
        case .unsafePath: "Control socket or its directory is not owned by this user or is unsafe."
        case .oversizedResponse: "Control response exceeds 64 KiB."
        case .invalidResponse: "Invalid control response."
        case .server(let message): message
        }
    }
}

private struct Configuration: Decodable {
    var dotfiles: String?
    var attentionFile: String?
    var clipboardFeedback: Bool?
    var terminalBorder: Bool?
    var zenMouse: Bool?
    var font: String?
    var glass: Bool?
    var musicFixture: String?

    enum CodingKeys: String, CodingKey {
        case dotfiles, font, glass
        case attentionFile = "attention_file"
        case clipboardFeedback = "clipboard_feedback"
        case terminalBorder = "terminal_border"
        case zenMouse = "zen_mouse"
        case musicFixture = "music_fixture"
    }
}

private let directory = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/Caches/DailyWorkspace", isDirectory: true)
private let socketURL = directory.appendingPathComponent("control.sock")
private let bundleIdentifier = "app.dailyworkspace.mac"
private let maxBytes = 65_536

private func request(from arguments: [String]) throws -> (json: [String: String], config: URL?) {
    var args = arguments
    var config: URL?
    if let index = args.firstIndex(of: "--config") {
        guard args.indices.contains(index + 1) else { throw ControlFailure.usage }
        config = URL(fileURLWithPath: args[index + 1])
        args.removeSubrange(index...index + 1)
    }
    return (try commandRequest(args), config)
}

private func commandRequest(_ args: [String]) throws -> [String: String] {
    guard let command = args.first else { throw ControlFailure.usage }
    switch command {
    case "show", "toggle":
        guard args.count == 2,
            [
                "home", "agents", "sessions", "files", "projects", "workspaces", "ssh", "tmux", "shortcuts",
                "attention", "system", "music", "calendar",
            ].contains(args[1])
        else { throw ControlFailure.usage }
        return ["action": command, "view": args[1]]
    case "mouse":
        guard args.count == 2, ["center", "corner"].contains(args[1]) else { throw ControlFailure.usage }
        return ["action": "mouse", "position": args[1]]
    case "hide", "status", "inspect", "clipboard":
        guard args.count == 1 else { throw ControlFailure.usage }
        return ["action": command]
    case "attention-refresh", "palette-reload":
        guard args.count == 1 else { throw ControlFailure.usage }
        return ["action": command == "attention-refresh" ? "attentionRefresh" : "paletteChanged"]
    default: throw ControlFailure.usage
    }
}

private func checkPath() throws {
    var dir = stat()
    if lstat(directory.path, &dir) != 0 {
        throw errno == ENOENT ? ControlFailure.unavailable : ControlFailure.unsafePath
    }
    guard dir.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), dir.st_uid == geteuid(),
        dir.st_mode & 0o777 == 0o700
    else { throw ControlFailure.unsafePath }
    var sock = stat()
    if lstat(socketURL.path, &sock) != 0 {
        throw errno == ENOENT ? ControlFailure.unavailable : ControlFailure.unsafePath
    }
    guard sock.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK), sock.st_uid == geteuid(),
        sock.st_mode & 0o777 == 0o600
    else { throw ControlFailure.unsafePath }
}

private func connect() throws -> Int32 {
    try checkPath()
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ControlFailure.unavailable }
    do {
        var address = sockaddr_un()
        let bytes = Array(socketURL.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ControlFailure.unsafePath }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) })
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw ControlFailure.unavailable }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else { throw ControlFailure.unsafePath }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        var noSignal: Int32 = 1
        _ = withUnsafePointer(to: &noSignal) {
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        return fd
    } catch {
        close(fd)
        throw error
    }
}

private func send(_ request: [String: String]) throws -> [String: Any] {
    let fd = try connect()
    defer { close(fd) }
    var bytes = try JSONSerialization.data(withJSONObject: request)
    bytes.append(10)
    guard bytes.count <= maxBytes else { throw ControlFailure.usage }
    try bytes.withUnsafeBytes { buffer in
        var sent = 0
        while sent < buffer.count {
            let count = write(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ControlFailure.unavailable }
            sent += count
        }
    }
    var response = Data()
    var byte: UInt8 = 0
    while true {
        let count = read(fd, &byte, 1)
        guard count > 0 else { throw ControlFailure.invalidResponse }
        if byte == 10 { break }
        guard response.count < maxBytes else { throw ControlFailure.oversizedResponse }
        response.append(byte)
    }
    guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
        let success = object["ok"] as? Bool
    else { throw ControlFailure.invalidResponse }
    guard success else { throw ControlFailure.server(object["error"] as? String ?? "Request failed") }
    return object
}

private func launch(config: URL?, action: String?) throws {
    // A running app may still be starting its listener; wait for it rather than launching a duplicate.
    if NSWorkspace.shared.runningApplications.contains(where: {
        $0.bundleIdentifier == bundleIdentifier || $0.executableURL?.lastPathComponent == "DailyWorkspace"
    }) {
        return
    }
    // `open` without -n reuses the registered app.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    var args = ["-g", "-b", bundleIdentifier]
    if ["paletteChanged", "attentionRefresh", "clipboard"].contains(action) {
        args += ["--args", "--background-control"]
    }
    if let config {
        if !args.contains("--args") { args.append("--args") }
        args += ["--config", config.path]
    }
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ControlFailure.unavailable }
}

private func main() throws {
    let parsed = try request(from: Array(CommandLine.arguments.dropFirst()))
    let configURL =
        parsed.config
        ?? URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".config/daily-workspace/quick-panel.json")
    do { _ = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL)) } catch let error
        as CocoaError where error.code == .fileReadNoSuchFile && parsed.config == nil
    {}

    let result: [String: Any]
    do { result = try send(parsed.json) } catch ControlFailure.unavailable {
        try launch(config: parsed.config, action: parsed.json["action"])
        let deadline = Date().addingTimeInterval(15)
        var answer: [String: Any]?
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            do {
                answer = try send(parsed.json)
                break
            } catch ControlFailure.unavailable { continue }
        }
        guard let answer else { throw ControlFailure.unavailable }
        result = answer
    }
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    guard let text = String(data: data, encoding: .utf8) else { throw ControlFailure.invalidResponse }
    print(text)
}

do {
    try main()
} catch {
    fputs("daily: \(error.localizedDescription)\n", stderr)
    exit(1)
}
