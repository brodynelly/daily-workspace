import Darwin
import Foundation

/// A fixed-argv helper invocation. Error descriptions never include arguments, environment, or child output.
enum QuickPanelCommandError: Error, Equatable, LocalizedError {
    case invalidExecutable
    case invalidArguments
    case launchFailed(Int32)
    case ioFailed
    case timedOut
    case exited(Int32)
    case outputTooLarge
    case signaled(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidExecutable: return "Helper executable must be an absolute file URL."
        case .invalidArguments: return "Helper arguments or environment are invalid."
        case .launchFailed: return "Could not launch the helper."
        case .exited(let status): return "Helper exited with status \(status)."
        case .ioFailed: return "Could not read the helper's output."
        case .timedOut: return "Helper exceeded its time limit."
        case .outputTooLarge: return "Helper output exceeded its size limit."
        case .signaled(let signal): return "Helper terminated with signal \(signal)."
        }
    }
}

struct QuickPanelCommandOutput: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let stdout: Data
    let exitStatus: Int32
    private let stderr: Data

    init(stdout: Data, exitStatus: Int32, stderr: Data = Data()) {
        self.stdout = stdout
        self.exitStatus = exitStatus
        self.stderr = stderr
    }

    /// Only a fixed HTTP status is extracted; raw stderr is never surfaced in descriptions or errors.
    var hasUnauthorizedHTTPStatusInStderr: Bool {
        guard let text = String(data: stderr, encoding: .utf8) else { return false }
        return text.range(of: #"\bHTTP[ \t]+40[13]\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The child's first stderr bytes, only for an on-screen message from a trusted local tool (the workspace Git
    /// hub). Never log it or put it in an error description.
    var stderrForDisplay: String { String(bytes: stderr, encoding: .utf8) ?? "" }

    var description: String { "Helper output (exit status \(exitStatus))" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["exitStatus": exitStatus]) }
}

/// Starts helpers off the caller's thread, with a process-group deadline and a combined stdout/stderr byte cap.
struct QuickPanelCommandRunner: Sendable {
    static let defaultTimeout: TimeInterval = 15
    static let defaultOutputLimit = 16 * 1024 * 1024

    let timeout: TimeInterval
    let outputLimit: Int

    init(timeout: TimeInterval = defaultTimeout, outputLimit: Int = defaultOutputLimit) {
        self.timeout = timeout
        self.outputLimit = outputLimit
    }

    func run(
        executable: URL, arguments: [String], environment: [String: String] = [:]
    ) async throws -> QuickPanelCommandOutput {
        try await run(executable: executable, arguments: arguments, environment: environment, onStdout: nil)
    }

    func runStreaming(
        executable: URL, arguments: [String], environment: [String: String],
        onStdout: @escaping @Sendable (Data) -> Void
    ) async throws -> QuickPanelCommandOutput {
        try await run(executable: executable, arguments: arguments, environment: environment, onStdout: onStdout)
    }

    private func run(
        executable: URL, arguments: [String], environment: [String: String],
        onStdout: (@Sendable (Data) -> Void)?
    ) async throws -> QuickPanelCommandOutput {
        guard executable.isFileURL, executable.path.hasPrefix("/") else {
            throw QuickPanelCommandError.invalidExecutable
        }
        guard !executable.path.contains("\0"), arguments.allSatisfy({ !$0.contains("\0") }),
            environment.allSatisfy({ !$0.key.contains("=") && !$0.key.contains("\0") && !$0.value.contains("\0") })
        else { throw QuickPanelCommandError.invalidArguments }
        let cancellation = CancellationState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let output = try execute(
                            executable: executable, arguments: arguments, environment: environment,
                            cancellation: cancellation, onStdout: onStdout)
                        continuation.resume(returning: output)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func execute(
        executable: URL, arguments: [String], environment: [String: String], cancellation: CancellationState,
        onStdout: (@Sendable (Data) -> Void)?
    ) throws -> QuickPanelCommandOutput {
        try cancellation.check()
        var stdoutPipe: [Int32] = [-1, -1]
        var stderrPipe: [Int32] = [-1, -1]
        guard pipe(&stdoutPipe) == 0 else { throw QuickPanelCommandError.ioFailed }
        defer {
            for fd in stdoutPipe where fd >= 0 { _ = close(fd) }
        }
        guard pipe(&stderrPipe) == 0 else { throw QuickPanelCommandError.ioFailed }
        defer {
            for fd in stderrPipe where fd >= 0 { _ = close(fd) }
        }
        try Self.configurePipe(stdoutPipe)
        try Self.configurePipe(stderrPipe)

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw QuickPanelCommandError.ioFailed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw QuickPanelCommandError.ioFailed }
        defer { posix_spawnattr_destroy(&attributes) }
        try Self.configureSpawn(
            actions: &actions, attributes: &attributes, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

        // Spawn takes C argv/envp, not a shell command string. Do not include either in errors or logs.
        let argv = try CStringArray([executable.path] + arguments)
        var childEnvironment: [String: String] = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "TMPDIR": FileManager.default.temporaryDirectory.path,
            "USER": NSUserName(),
            "LANG": "en_US.UTF-8",
        ]
        childEnvironment.merge(environment) { _, replacement in replacement }
        childEnvironment["PATH"] =
            "/opt/homebrew/bin:/usr/local/bin:"
            + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        let envp = try CStringArray(childEnvironment.map { "\($0.key)=\($0.value)" })
        var pid: pid_t = 0
        let spawnStatus = executable.path.withCString { path in
            posix_spawn(&pid, path, &actions, &attributes, argv.pointers, envp.pointers)
        }
        guard spawnStatus == 0 else { throw QuickPanelCommandError.launchFailed(spawnStatus) }
        // The group is established atomically before exec. Keep the leader unreaped while pipes are open,
        // so neither the PID nor its group can be reused before timeout/cancellation cleanup.
        cancellation.register(pid)
        _ = close(stdoutPipe[1])
        stdoutPipe[1] = -1
        _ = close(stderrPipe[1])
        stderrPipe[1] = -1
        defer { cancellation.unregister() }
        do {
            let output = try collect(
                stdout: stdoutPipe[0], stderr: stderrPipe[0], pid: pid, cancellation: cancellation,
                onStdout: onStdout)
            if (output.status & 0x7f) == 0 {
                let exitCode = (output.status >> 8) & 0xff
                return QuickPanelCommandOutput(stdout: output.stdout, exitStatus: exitCode, stderr: output.stderr)
            }
            throw QuickPanelCommandError.signaled(output.status & 0x7f)
        } catch {
            if cancellation.killRunningGroup() { reap(pid) }
            throw error
        }
    }

    private static func configurePipe(_ descriptors: [Int32]) throws {
        for fd in descriptors {
            guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw QuickPanelCommandError.ioFailed }
        }
        let flags = fcntl(descriptors[0], F_GETFL)
        guard flags >= 0, fcntl(descriptors[0], F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw QuickPanelCommandError.ioFailed
        }
    }

    private static func configureSpawn(
        actions: inout posix_spawn_file_actions_t?, attributes: inout posix_spawnattr_t?,
        stdoutPipe: [Int32], stderrPipe: [Int32]
    ) throws {
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
            posix_spawnattr_setpgroup(&attributes, 0) == 0,
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
            posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO) == 0,
            posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO) == 0,
            posix_spawn_file_actions_addclose(&actions, stdoutPipe[0]) == 0,
            posix_spawn_file_actions_addclose(&actions, stderrPipe[0]) == 0,
            posix_spawn_file_actions_addclose(&actions, stdoutPipe[1]) == 0,
            posix_spawn_file_actions_addclose(&actions, stderrPipe[1]) == 0
        else { throw QuickPanelCommandError.ioFailed }
    }

    private struct CollectedOutput {
        let stdout: Data
        let stderr: Data
        let status: Int32
    }

    private struct OutputAccumulator {
        var stdout = Data()
        var stderr = Data()
        var total = 0
    }

    private func collect(
        stdout: Int32, stderr: Int32, pid: pid_t, cancellation: CancellationState,
        onStdout: (@Sendable (Data) -> Void)?
    ) throws -> CollectedOutput {
        var output = OutputAccumulator()
        var open = [true, true]
        let descriptors = [stdout, stderr]
        var buffer = [UInt8](repeating: 0, count: 8192)
        var pollDescriptors = [
            pollfd(fd: stdout, events: Int16(POLLIN | POLLHUP), revents: 0),
            pollfd(fd: stderr, events: Int16(POLLIN | POLLHUP), revents: 0),
        ]
        let duration = UInt64(max(0, timeout) * 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds &+ duration
        while true {
            try cancellation.check()
            if DispatchTime.now().uptimeNanoseconds >= deadline { throw QuickPanelCommandError.timedOut }
            var didRead = false
            for index in descriptors.indices where open[index] {
                let count = try readAvailable(
                    descriptors[index], isStderr: index == 1, buffer: &buffer, output: &output,
                    onStdout: onStdout)
                if count > 0 { didRead = true }
                if count == 0 { open[index] = false }
            }
            if !open[0] && !open[1] {
                if let status = try cancellation.pollExit(pid) {
                    return CollectedOutput(stdout: output.stdout, stderr: output.stderr, status: status)
                }
            }
            if !didRead {
                pollDescriptors[0].events = open[0] ? Int16(POLLIN | POLLHUP) : 0
                pollDescriptors[1].events = open[1] ? Int16(POLLIN | POLLHUP) : 0
                _ = poll(&pollDescriptors, nfds_t(pollDescriptors.count), 10)
            }
        }
    }

    private func readAvailable(
        _ fd: Int32, isStderr: Bool, buffer: inout [UInt8], output: inout OutputAccumulator,
        onStdout: (@Sendable (Data) -> Void)?
    ) throws -> Int {
        let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        if count > 0 {
            if count > outputLimit - output.total { throw QuickPanelCommandError.outputTooLarge }
            output.total += count
            if isStderr {
                if output.stderr.count < 4096 {
                    output.stderr.append(contentsOf: buffer[..<min(count, 4096 - output.stderr.count)])
                }
            } else if let onStdout {
                onStdout(Data(buffer[..<count]))
                if output.stdout.count < 4096 {
                    output.stdout.append(contentsOf: buffer[..<min(count, 4096 - output.stdout.count)])
                }
            } else {
                output.stdout.append(contentsOf: buffer[..<count])
            }
        } else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
            throw QuickPanelCommandError.ioFailed
        }
        return count
    }

    private func reap(_ pid: pid_t) {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    }
}

/// Cancellation can arrive before spawn, while running, or while the caller is suspended.
private final class CancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var pid: pid_t = 0

    func cancel() {
        lock.lock()
        cancelled = true
        if pid > 0 { _ = kill(-pid, SIGKILL) }
        lock.unlock()
    }

    func register(_ process: pid_t) {
        lock.lock()
        pid = process
        if cancelled { _ = kill(-pid, SIGKILL) }
        lock.unlock()
    }

    /// Keep the leader waitable until every remaining process in its group has been signaled.
    func pollExit(_ process: pid_t) throws -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        var info = siginfo_t()
        if waitid(P_PID, id_t(process), &info, WEXITED | WNOHANG | WNOWAIT) != 0 {
            if errno == EINTR { return nil }
            throw QuickPanelCommandError.ioFailed
        }
        guard info.si_signo != 0 else { return nil }
        // A pipe-closing descendant can survive the leader. WNOWAIT prevents group-ID reuse
        // until after the entire group has been killed and the leader is reaped.
        _ = kill(-process, SIGKILL)
        var status: Int32 = 0
        var waited: pid_t
        repeat { waited = waitpid(process, &status, 0) } while waited == -1 && errno == EINTR
        guard waited == process else { throw QuickPanelCommandError.ioFailed }
        pid = 0
        return status
    }

    func killRunningGroup() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pid > 0 else { return false }
        _ = kill(-pid, SIGKILL)
        return true
    }

    func unregister() {
        lock.lock()
        pid = 0
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        let isCancelled = cancelled
        lock.unlock()
        if isCancelled { throw CancellationError() }
    }
}

private final class CStringArray {
    let pointers: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>

    init(_ strings: [String]) throws {
        pointers = .allocate(capacity: strings.count + 1)
        for index in strings.indices {
            guard let value = strdup(strings[index]) else {
                for prior in 0..<index { free(pointers[prior]) }
                pointers.deallocate()
                throw QuickPanelCommandError.ioFailed
            }
            pointers[index] = value
        }
        pointers[strings.count] = nil
    }

    deinit {
        var index = 0
        while let value = pointers[index] {
            free(value)
            index += 1
        }
        pointers.deallocate()
    }
}
