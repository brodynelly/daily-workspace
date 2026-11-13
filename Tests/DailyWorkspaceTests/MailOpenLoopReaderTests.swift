import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

private final class StubMailResponseSource: MailResponseSource, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let result: MailReadResult

    init(_ result: MailReadResult) { self.result = result }

    func read() -> MailReadResult {
        lock.withLock { calls += 1 }
        return result
    }

    var readCount: Int { lock.withLock { calls } }
}

final class MailOpenLoopReaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_518_400)

    func testNoMailAccessWithoutExplicitOptIn() {
        let source = StubMailResponseSource(
            .data(rows: [["id", "Private subject", "flagged status: true"]], incomplete: false))
        let reader = MailOpenLoopReader(responseSource: source)

        let observation = reader.readLoops(now: now)

        XCTAssertEqual(source.readCount, 0)
        XCTAssertEqual(observation.state, .unauthorized)
        XCTAssertTrue(observation.value.isEmpty)
        XCTAssertNil(observation.lastSuccessAt)
    }

    func testDisablingAfterAReadDoesNotReturnPreviousMailMetadata() {
        let privateSubject = "Private subject"
        let source = StubMailResponseSource(
            .data(rows: [["private-id", privateSubject, "flagged status: true"]], incomplete: false))
        let enabled = MailOpenLoopReader(enabled: true, responseSource: source).readLoops(now: now)
        XCTAssertEqual(enabled.value.first?.title, privateSubject)

        let disabled = MailOpenLoopReader(enabled: false, responseSource: source).readLoops(now: now)

        XCTAssertEqual(source.readCount, 1)
        XCTAssertEqual(disabled.state, .unauthorized)
        XCTAssertTrue(disabled.value.isEmpty)
        XCTAssertNil(disabled.lastSuccessAt)
        XCTAssertTrue(disabled.state.issues.isEmpty)
    }

    func testRevokedAuthorizationSkipsQueuedReaderBeforeResponseSource() {
        let source = StubMailResponseSource(.data(rows: [["id", "Private", "read status: false"]], incomplete: false))
        let authorization = MailReadAuthorization()
        authorization.revoke()

        let observation = MailOpenLoopReader(enabled: true, responseSource: source)
            .readLoops(now: now, authorization: authorization)

        XCTAssertEqual(source.readCount, 0)
        XCTAssertEqual(observation.state, .unauthorized)
        XCTAssertTrue(observation.value.isEmpty)
        XCTAssertNil(observation.lastSuccessAt)
    }

    func testDeniedMailAccessIsNotEmptyWork() {
        let source = StubMailResponseSource(.unauthorized)
        let observation = MailOpenLoopReader(enabled: true, responseSource: source).readLoops(now: now)

        XCTAssertEqual(source.readCount, 1)
        XCTAssertEqual(observation.state, .unauthorized)
        XCTAssertTrue(observation.value.isEmpty)
        XCTAssertNil(observation.lastSuccessAt)
    }

    func testUnsupportedAndUnavailableAreNotEmptyWork() {
        let unsupported = MailOpenLoopReader(enabled: true, responseSource: StubMailResponseSource(.unsupported))
            .readLoops(now: now)
        let unavailable = MailOpenLoopReader(enabled: true, responseSource: StubMailResponseSource(.unavailable))
            .readLoops(now: now)

        XCTAssertEqual(unsupported.state, .unsupported)
        guard case .unavailable = unavailable.state else { return XCTFail("Expected unavailable Mail") }
        XCTAssertFalse(unsupported.state.isReadable)
        XCTAssertFalse(unavailable.state.isReadable)
        XCTAssertTrue(unsupported.value.isEmpty)
        XCTAssertTrue(unavailable.value.isEmpty)
    }

    func testSuccessfulEmptyReadIsExplicit() {
        let observation = MailOpenLoopReader(
            enabled: true, responseSource: StubMailResponseSource(.data(rows: [], incomplete: false))
        ).readLoops(now: now)

        XCTAssertEqual(observation.state, .empty)
        XCTAssertEqual(observation.lastSuccessAt, now)
        XCTAssertTrue(observation.value.isEmpty)
    }

    func testFlaggedAndUnreadImportantPreserveNativeStatusAndMailIDs() {
        let rows = [
            ["<first@example.test>", "Flagged subject", "flagged status: true"],
            ["<second@example.test>", "Important subject", "read status: false"],
        ]
        let observation = MailOpenLoopReader(
            enabled: true, responseSource: StubMailResponseSource(.data(rows: rows, incomplete: false))
        ).readLoops(now: now)

        XCTAssertEqual(observation.state, .populated)
        XCTAssertEqual(observation.value.map(\.id), ["mail:<first@example.test>", "mail:<second@example.test>"])
        XCTAssertEqual(observation.value.map(\.title), ["Flagged subject", "Important subject"])
        XCTAssertEqual(
            observation.value.map(\.nativeStatus), ["flagged status: true", "read status: false"])
        XCTAssertTrue(
            observation.value.allSatisfy { $0.authority == .mail && !$0.isDoneInSource && $0.observedAt == now })
        XCTAssertTrue(observation.value.allSatisfy { $0.sourcePath == nil && $0.project == nil })
    }

    func testMalformedRowsProducePartialWithoutLeakingMetadataIntoIssues() {
        let privateSubject = "Confidential subject"
        let rows = [
            ["id-one", "Valid subject", "flagged status: true"],
            ["id-two", privateSubject],
            ["id-three", privateSubject, "unknown status"],
            ["", privateSubject, "flagged status: true"],
        ]
        let observation = MailOpenLoopReader(
            enabled: true, responseSource: StubMailResponseSource(.data(rows: rows, incomplete: true))
        ).readLoops(now: now)

        guard case .partial(let issues) = observation.state else { return XCTFail("Expected partial Mail read") }
        XCTAssertEqual(observation.value.map(\.id), ["mail:id-one"])
        XCTAssertEqual(issues.count, 2)
        XCTAssertFalse(issues.map(\.description).joined().contains(privateSubject))
        XCTAssertEqual(observation.lastSuccessAt, now)
    }

    func testDuplicateMessageIDsAreShownOnce() {
        let rows = [
            ["message-id", "Flagged subject", "flagged status: true"],
            ["message-id", "Important subject", "read status: false"],
        ]
        let observation = MailOpenLoopReader(
            enabled: true, responseSource: StubMailResponseSource(.data(rows: rows, incomplete: false))
        ).readLoops(now: now)

        XCTAssertEqual(observation.state, .populated)
        XCTAssertEqual(observation.value.count, 1)
        XCTAssertEqual(observation.value.first?.nativeStatus, "flagged status: true")
    }

    func testOutputCapsMarkIncompleteRatherThanClaimingFullRead() {
        let rows = (0...MailOpenLoopReader.maximumRows).map {
            ["id-\($0)", "Subject", "flagged status: true"]
        }
        let observation = MailOpenLoopReader(
            enabled: true, responseSource: StubMailResponseSource(.data(rows: rows, incomplete: false))
        ).readLoops(now: now)

        guard case .partial = observation.state else { return XCTFail("Expected partial capped Mail read") }
        XCTAssertEqual(observation.value.count, MailOpenLoopReader.maximumRows)
    }
}
