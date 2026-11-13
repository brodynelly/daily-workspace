import Darwin
import Foundation

/// The only messages accepted from the local socket. No request may carry a tool, path, or command.
enum QuickPanelControlAction: Equatable {
    case show(QuickPanelRoute), toggle(QuickPanelRoute), hide, status, inspect
    case refresh, attentionRefresh, paletteChanged, quit, clipboard, mouse(String)

    init(json: Any) throws {
        guard let object = json as? [String: Any], let name = object["action"] as? String else {
            throw QuickPanelControlError.invalidRequest
        }
        let fields: Set<String>
        switch name {
        case "show", "toggle":
            fields = ["action", "view"]
            guard let view = object["view"] as? String, let route = QuickPanelRoute(rawValue: view) else {
                throw QuickPanelControlError.invalidRequest
            }
            self = name == "show" ? .show(route) : .toggle(route)
        case "mouse":
            fields = ["action", "position"]
            guard let position = object["position"] as? String, position == "center" || position == "corner" else {
                throw QuickPanelControlError.invalidRequest
            }
            self = .mouse(position)
        default:
            fields = ["action"]
            guard let action = Self.simpleAction(named: name) else { throw QuickPanelControlError.invalidRequest }
            self = action
        }
        guard Set(object.keys) == fields else { throw QuickPanelControlError.invalidRequest }
    }

    private static func simpleAction(named name: String) -> Self? {
        switch name {
        case "hide": .hide
        case "status": .status
        case "inspect": .inspect
        case "refresh": .refresh
        case "attentionRefresh": .attentionRefresh
        case "paletteChanged": .paletteChanged
        case "quit": .quit
        case "clipboard": .clipboard
        default: nil
        }
    }
}

enum QuickPanelControlError: Error, Equatable, LocalizedError {
    case unsafeDirectory, unsafeLock, unsafeSocket, alreadyRunning, unauthorizedPeer, invalidRequest
    case messageTooLarge, incompleteMessage, ioFailure(Int32)

    var errorDescription: String? {
        switch self {
        case .unsafeDirectory: "IPC directory must be owned by this user, private, and not a symlink."
        case .unsafeLock: "IPC lock must be a private, owned regular file without symlinks."
        case .unsafeSocket: "IPC socket must be an owned socket without symlinks."
        case .alreadyRunning: "Daily Workspace control service is already running."
        case .unauthorizedPeer: "Unauthorized IPC peer."
        case .invalidRequest: "IPC only accepts panel lifecycle and notification commands."
        case .messageTooLarge: "Request exceeds 64 KiB."
        case .incompleteMessage: "Request must end with a newline."
        case .ioFailure(let number): "IPC system error \(number)."
        }
    }
}

/// Owns the socket and exclusive lock for the lifetime of the app. Bind once at app startup;
/// invoke `start` with an injected main-actor callback to bridge to QuickPanelController.
final class QuickPanelControlServer {
    static let defaultDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Caches/DailyWorkspace", isDirectory: true)
    static let maxMessageBytes = 65_536
    private static let requestTimeoutNanoseconds: UInt64 = 2_000_000_000

    let directory: URL
    var socketURL: URL { directory.appendingPathComponent("control.sock") }
    private let lockFD: Int32
    private let listenerFD: Int32
    private let socketIdentity: (dev_t, ino_t)
    private let peerUID: (Int32) -> uid_t?
    private let state = NSLock()
    private var stopped = false

    init(
        directory: URL = defaultDirectory,
        peerUID: @escaping (Int32) -> uid_t? = { fd in
            var uid: uid_t = 0
            var gid: gid_t = 0
            return getpeereid(fd, &uid, &gid) == 0 ? uid : nil
        }
    ) throws {
        self.directory = directory
        self.peerUID = peerUID
        let dirFD = try Self.openDirectory(directory.path)
        defer { close(dirFD) }
        let lock = try Self.lockService(in: dirFD)
        do {
            try Self.removeOldSocket(in: dirFD)
            let listener = socket(AF_UNIX, SOCK_STREAM, 0)
            guard listener >= 0 else { throw QuickPanelControlError.ioFailure(errno) }
            do {
                let identity = try Self.startListener(
                    listener, path: directory.appendingPathComponent("control.sock").path, in: dirFD)
                lockFD = lock
                listenerFD = listener
                socketIdentity = (identity.st_dev, identity.st_ino)
            } catch {
                close(listener)
                _ = unlinkat(dirFD, "control.sock", 0)
                throw error
            }
        } catch {
            close(lock)
            throw error
        }
    }

    private static func openDirectory(_ path: String) throws -> Int32 {
        if mkdir(path, 0o700) != 0 && errno != EEXIST { throw QuickPanelControlError.ioFailure(errno) }
        var dirInfo = stat()
        guard lstat(path, &dirInfo) == 0,
            dirInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), dirInfo.st_uid == geteuid()
        else { throw QuickPanelControlError.unsafeDirectory }
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw QuickPanelControlError.unsafeDirectory }
        do {
            var verified = stat()
            guard fstat(fd, &verified) == 0,
                verified.st_ino == dirInfo.st_ino, verified.st_dev == dirInfo.st_dev,
                fchmod(fd, 0o700) == 0
            else { throw QuickPanelControlError.unsafeDirectory }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    private static func lockService(in dirFD: Int32) throws -> Int32 {
        let lock = openat(dirFD, "service.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw QuickPanelControlError.unsafeLock }
        do {
            var info = stat()
            guard fstat(lock, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                info.st_uid == geteuid(), info.st_nlink == 1,
                fchmod(lock, 0o600) == 0
            else { throw QuickPanelControlError.unsafeLock }
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw QuickPanelControlError.alreadyRunning }
            return lock
        } catch {
            close(lock)
            throw error
        }
    }

    private static func removeOldSocket(in dirFD: Int32) throws {
        var oldSocket = stat()
        if fstatat(dirFD, "control.sock", &oldSocket, AT_SYMLINK_NOFOLLOW) == 0 {
            guard oldSocket.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK),
                oldSocket.st_uid == geteuid()
            else { throw QuickPanelControlError.unsafeSocket }
            guard unlinkat(dirFD, "control.sock", 0) == 0 else { throw QuickPanelControlError.ioFailure(errno) }
        } else if errno != ENOENT {
            throw QuickPanelControlError.ioFailure(errno)
        }
    }

    private static func startListener(_ listener: Int32, path: String, in dirFD: Int32) throws -> stat {
        try QuickPanelSocketBinding.bind(listener, path: path)
        guard chmod(path, 0o600) == 0, listen(listener, 16) == 0 else {
            throw QuickPanelControlError.ioFailure(errno)
        }
        var identity = stat()
        guard fstatat(dirFD, "control.sock", &identity, AT_SYMLINK_NOFOLLOW) == 0,
            identity.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK),
            identity.st_uid == geteuid(), identity.st_mode & 0o777 == 0o600
        else { throw QuickPanelControlError.unsafeSocket }
        return identity
    }

    deinit { stop() }

    func stop() {
        state.lock()
        defer { state.unlock() }
        guard !stopped else { return }
        stopped = true
        _ = shutdown(listenerFD, SHUT_RDWR)
        close(listenerFD)
        let dirFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if dirFD >= 0 {
            var info = stat()
            if fstatat(dirFD, "control.sock", &info, AT_SYMLINK_NOFOLLOW) == 0,
                info.st_dev == socketIdentity.0, info.st_ino == socketIdentity.1
            {
                _ = unlinkat(dirFD, "control.sock", 0)
            }
            close(dirFD)
        }
        close(lockFD)
    }

    func start(handler: @escaping @MainActor @Sendable (QuickPanelControlAction) -> [String: Any]) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            while true {
                let fd = accept(listenerFD, nil, nil)
                if fd < 0 {
                    state.lock()
                    let finished = stopped
                    state.unlock()
                    if finished { break }
                    continue
                }
                handle(fd, handler: handler)
                close(fd)
            }
        }
    }

    private func handle(_ fd: Int32, handler: @escaping @MainActor @Sendable (QuickPanelControlAction) -> [String: Any])
    {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
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
        do {
            guard peerUID(fd) == geteuid() else { throw QuickPanelControlError.unauthorizedPeer }
            let action = try Self.decodeRequest(fd)
            let response: [String: Any]
            if action == .status {
                let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
                response = [
                    "ok": true, "pid": ProcessInfo.processInfo.processIdentifier,
                    "protocol": 1, "version": version,
                ]
            } else {
                let signal = DispatchSemaphore(value: 0)
                let answer = ResponseBox()
                Task { @MainActor in
                    answer.value = handler(action)
                    signal.signal()
                }
                signal.wait()
                response = answer.value ?? ["ok": false, "error": "Service unavailable"]
            }
            try Self.writeResponse(response, to: fd)
        } catch {
            try? Self.writeResponse(["ok": false, "error": error.localizedDescription], to: fd)
        }
    }

    private final class ResponseBox: @unchecked Sendable {
        var value: [String: Any]?
    }

    static func decodeRequest(_ fd: Int32) throws -> QuickPanelControlAction {
        let deadline = DispatchTime.now().uptimeNanoseconds + requestTimeoutNanoseconds
        var data = Data()
        while true {
            let byte = try readByte(fd, before: deadline)
            if byte == 10 { break }
            guard data.count < maxMessageBytes else { throw QuickPanelControlError.messageTooLarge }
            data.append(byte)
        }
        return try QuickPanelControlAction(json: JSONSerialization.jsonObject(with: data))
    }

    private static func readByte(_ fd: Int32, before deadline: UInt64) throws -> UInt8 {
        var byte: UInt8 = 0
        while true {
            try waitForReadable(fd, before: deadline)
            let count = read(fd, &byte, 1)
            if count == 0 { throw QuickPanelControlError.incompleteMessage }
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw QuickPanelControlError.ioFailure(errno)
            }
            return byte
        }
    }

    private static func waitForReadable(_ fd: Int32, before deadline: UInt64) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw QuickPanelControlError.incompleteMessage }
            var pending = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32((deadline - now + 999_999) / 1_000_000)
            let ready = poll(&pending, 1, milliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                throw QuickPanelControlError.ioFailure(errno)
            }
            guard ready > 0, DispatchTime.now().uptimeNanoseconds < deadline else {
                throw QuickPanelControlError.incompleteMessage
            }
            if pending.revents & Int16(POLLNVAL) != 0 { throw QuickPanelControlError.ioFailure(EBADF) }
            return
        }
    }

    private static func writeResponse(_ json: [String: Any], to fd: Int32) throws {
        var bytes = try JSONSerialization.data(withJSONObject: json)
        bytes.append(10)
        guard bytes.count <= maxMessageBytes else { throw QuickPanelControlError.messageTooLarge }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw QuickPanelControlError.ioFailure(errno) }
                offset += written
            }
        }
    }

}

/// Encodes the local socket address without exposing arbitrary paths to control requests.
private enum QuickPanelSocketBinding {
    static func bind(_ fd: Int32, path: String) throws {
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw QuickPanelControlError.unsafeSocket
        }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: bytes.map { UInt8(bitPattern: $0) })
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw QuickPanelControlError.ioFailure(errno) }
    }
}
