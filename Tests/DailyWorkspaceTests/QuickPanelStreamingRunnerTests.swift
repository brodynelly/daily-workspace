import Foundation
import XCTest

@testable import DailyWorkspace

private final class StreamingWitness: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    let firstChunk: XCTestExpectation

    init(firstChunk: XCTestExpectation) { self.firstChunk = firstChunk }
    var contents: Data { lock.withLock { bytes } }
    func receive(_ data: Data) {
        let first = lock.withLock {
            let wasEmpty = bytes.isEmpty
            bytes.append(data)
            return wasEmpty
        }
        if first { firstChunk.fulfill() }
    }
}

final class QuickPanelStreamingRunnerTests: XCTestCase {
    func testReceivesChunkWhileChildWaitsAndStillBoundsProcess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("continue")
        let witness = StreamingWitness(firstChunk: expectation(description: "first stdout chunk"))
        let runner = QuickPanelCommandRunner(timeout: 3, outputLimit: 128)
        let task = Task {
            try await runner.runStreaming(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c", "printf 'first\\n'; while [ ! -e \"$1\" ]; do sleep 0.02; done; printf 'last\\n'", "sh",
                    marker.path,
                ],
                environment: [:], onStdout: { witness.receive($0) })
        }
        await fulfillment(of: [witness.firstChunk], timeout: 1)
        XCTAssertEqual(witness.contents, Data("first\n".utf8))
        try Data().write(to: marker)
        let result = try await task.value
        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertEqual(witness.contents, Data("first\nlast\n".utf8))
    }
}
