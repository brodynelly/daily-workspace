import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

private actor FollowCommandSpy: LuunaChunkRunning {
    private var recorded: [[String]] = []
    private var environments: [[String: String]] = []

    var commands: [[String]] { recorded }
    var credentials: [[String: String]] { environments }

    func runStreaming(
        executable: URL, arguments: [String], environment: [String: String],
        onStdout: @escaping @Sendable (Data) -> Void
    ) async throws -> QuickPanelCommandOutput {
        recorded.append(arguments)
        environments.append(environment)
        onStdout(Data("{\"sequence\":1,\"run_id\":\"r\",\"project_id\":\"p\",\"type\":\"run.started\"}\n".utf8))
        return QuickPanelCommandOutput(stdout: Data(), exitStatus: 0)
    }
}

final class LuunaCLIFollowTests: XCTestCase {
    func testFollowUsesOnlyReadOnlyFixedArgvAndCurrentCredentials() async throws {
        let spy = FollowCommandSpy()
        let reader = LuunaCLIReader(
            executable: URL(fileURLWithPath: "/Users/fixture/.local/bin/lu"), streamer: spy)
        let connection = LuunaConnection(origin: .standard, token: "fixture-token")
        let received = FollowChunks()
        try await reader.follow("r", after: 7, connection) { received.append($0) }
        let calls = await spy.commands
        let credentials = await spy.credentials
        XCTAssertEqual(calls, [["follow", "r", "--after", "7", "--json"]])
        XCTAssertEqual(
            credentials,
            [
                [
                    "LUUNA_URL": LuunaOrigin.standard.description, "LUUNA_API_TOKEN": "fixture-token",
                    "LUUNA_NO_AUTO_START": "1",
                ]
            ])
        XCTAssertNotNil(received.contents.range(of: Data(#""type":"run.started""#.utf8)))
        do {
            try await reader.follow("r", after: -1, connection) { _ in }
            XCTFail("Negative cursor must be refused")
        } catch let failure as LuunaReadFailure {
            XCTAssertEqual(failure.state, .refused(LuunaRefusal(status: 0, reason: nil)))
        }
        let count = await spy.commands.count
        XCTAssertEqual(count, 1)
    }
}

private final class FollowChunks: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks = Data()
    var contents: Data { lock.withLock { chunks } }
    func append(_ data: Data) { lock.withLock { chunks.append(data) } }
}
