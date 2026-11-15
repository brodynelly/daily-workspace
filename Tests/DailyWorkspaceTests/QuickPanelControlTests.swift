import Darwin
import Foundation
import XCTest

@testable import DailyWorkspace

final class QuickPanelControlTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("dc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func connect(socketURL: URL) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw QuickPanelControlError.ioFailure(errno) }
        var address = sockaddr_un()
        let path = Array(socketURL.path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: path.map { UInt8(bitPattern: $0) })
        }
        address.sun_family = sa_family_t(AF_UNIX)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let error = errno
            close(fd)
            throw QuickPanelControlError.ioFailure(error)
        }
        return fd
    }

    private func exchange(_ json: String, socketURL: URL, responseTimeoutSeconds: Int32 = 2) throws -> [String: Any] {
        let fd = try connect(socketURL: socketURL)
        defer { close(fd) }
        var timeout = timeval(tv_sec: numericCast(responseTimeoutSeconds), tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        let bytes = Array((json + "\n").utf8)
        bytes.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let count = write(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
                guard count > 0 else {
                    XCTFail("Failed to send request")
                    break
                }
                sent += count
            }
        }
        var data = Data()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 10 { break }
            data.append(byte)
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testStatusAndValidNavigationWithoutAutomation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("private")
        let server = try QuickPanelControlServer(directory: directory)
        defer { server.stop() }
        let received = expectation(description: "main actor navigation callback")
        server.start { action in
            if action == .show(.shortcuts) { received.fulfill() }
            return ["ok": true, "queued": true]
        }
        let status = try exchange(#"{"action":"status"}"#, socketURL: server.socketURL)
        XCTAssertEqual(status["ok"] as? Bool, true)
        XCTAssertEqual(status["pid"] as? Int32, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(status["protocol"] as? Int, 1)
        let show = try await Task.detached {
            try self.exchange(#"{"action":"show","view":"shortcuts"}"#, socketURL: server.socketURL)
        }.value
        XCTAssertEqual(show["queued"] as? Bool, true)
        await fulfillment(of: [received], timeout: 2)
        var directoryInfo = stat()
        var socketInfo = stat()
        XCTAssertEqual(lstat(directory.path, &directoryInfo), 0)
        XCTAssertEqual(directoryInfo.st_mode & 0o777, 0o700)
        XCTAssertEqual(lstat(server.socketURL.path, &socketInfo), 0)
        XCTAssertEqual(socketInfo.st_mode & 0o777, 0o600)
        XCTAssertThrowsError(try QuickPanelControlServer(directory: directory)) {
            XCTAssertEqual($0 as? QuickPanelControlError, .alreadyRunning)
        }
    }

    func testRejectsExecutionAndUnknownViews() throws {
        for request in [
            #"{"action":"launch","tool":"sh","path":"/tmp"}"#,
            #"{"action":"system","command":"restart"}"#,
            #"{"action":"show","view":"../../tmp"}"#,
            #"{"action":"show","view":"home","path":"/tmp"}"#,
            #"{"action":"mouse","position":"somewhere"}"#,
            #"{"action":"login","mode":"toggle"}"#,
            #"{"action":"login","mode":"enable","path":"/tmp"}"#,
            #"{"action":"login"}"#,
        ] {
            let value = try JSONSerialization.jsonObject(with: Data(request.utf8))
            XCTAssertThrowsError(try QuickPanelControlAction(json: value)) {
                XCTAssertEqual($0 as? QuickPanelControlError, .invalidRequest)
            }
        }
        XCTAssertEqual(
            try QuickPanelControlAction(json: ["action": "login", "mode": "enable"]), .login("enable"))
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try QuickPanelControlServer(directory: root.appendingPathComponent("private"))
        defer { server.stop() }
        server.start { _ in
            XCTFail("Invalid message reached callback")
            return ["ok": true]
        }
        let rejected = try exchange(#"{"action":"launch","tool":"sh"}"#, socketURL: server.socketURL)
        XCTAssertEqual(rejected["ok"] as? Bool, false)
    }

    func testRejectsUnauthorizedPeerBeforeDispatch() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try QuickPanelControlServer(
            directory: root.appendingPathComponent("private"), peerUID: { _ in geteuid() + 1 })
        defer { server.stop() }
        server.start { _ in
            XCTFail("Unauthorized peer reached callback")
            return ["ok": true]
        }
        let rejected = try exchange(#"{"action":"status"}"#, socketURL: server.socketURL)
        XCTAssertEqual(rejected["ok"] as? Bool, false)
        XCTAssertEqual(rejected["error"] as? String, QuickPanelControlError.unauthorizedPeer.localizedDescription)
    }

    func testRejectsUnsafeDirectoriesLocksAndSocketPaths() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        XCTAssertThrowsError(try QuickPanelControlServer(directory: alias)) {
            XCTAssertEqual($0 as? QuickPanelControlError, .unsafeDirectory)
        }
        let lockDir = root.appendingPathComponent("lockdir")
        try FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: lockDir.appendingPathComponent("service.lock"), withDestinationURL: real)
        XCTAssertThrowsError(try QuickPanelControlServer(directory: lockDir)) {
            XCTAssertEqual($0 as? QuickPanelControlError, .unsafeLock)
        }
        let socketDir = root.appendingPathComponent("socketdir")
        try FileManager.default.createDirectory(at: socketDir, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: socketDir.appendingPathComponent("control.sock"), withDestinationURL: real)
        XCTAssertThrowsError(try QuickPanelControlServer(directory: socketDir)) {
            XCTAssertEqual($0 as? QuickPanelControlError, .unsafeSocket)
        }
    }

    func testRejectsOversizedMessages() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try QuickPanelControlServer(directory: root.appendingPathComponent("private"))
        defer { server.stop() }
        server.start { _ in
            XCTFail("Oversized request reached callback")
            return ["ok": true]
        }
        let rejected = try exchange(
            String(repeating: "a", count: QuickPanelControlServer.maxMessageBytes + 1), socketURL: server.socketURL)
        XCTAssertEqual(rejected["ok"] as? Bool, false)
        XCTAssertEqual(rejected["error"] as? String, QuickPanelControlError.messageTooLarge.localizedDescription)
    }

    func testSlowDripDoesNotBlockFollowingClient() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try QuickPanelControlServer(directory: root.appendingPathComponent("private"))
        defer { server.stop() }
        server.start { _ in
            XCTFail("Incomplete message reached callback")
            return ["ok": true]
        }

        let slow = try connect(socketURL: server.socketURL)
        defer { close(slow) }
        var noSignal: Int32 = 1
        let configured = withUnsafePointer(to: &noSignal) {
            setsockopt(slow, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        guard configured == 0 else { throw QuickPanelControlError.ioFailure(errno) }
        let drip = DispatchGroup()
        defer { drip.wait() }
        var first: UInt8 = 123
        guard write(slow, &first, 1) == 1 else { throw QuickPanelControlError.ioFailure(errno) }
        drip.enter()
        DispatchQueue.global().async {
            defer { drip.leave() }
            var byte: UInt8 = 32
            for _ in 0..<12 {
                usleep(350_000)
                if write(slow, &byte, 1) != 1 { break }
            }
        }

        let started = DispatchTime.now().uptimeNanoseconds
        let healthy = try exchange(#"{"action":"status"}"#, socketURL: server.socketURL, responseTimeoutSeconds: 4)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        XCTAssertEqual(healthy["ok"] as? Bool, true)
        XCTAssertLessThan(elapsed, 3.8, "A trickling peer must not hold the listener beyond the request deadline")
    }
}
