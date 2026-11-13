import DailyCore
import XCTest

@testable import DailyWorkspace

/// A deterministic Mail boundary; can hold a response while consent or the vault changes.
final class FakeMailResponseSource: MailResponseSource, @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var response: MailReadResult
    private var readCount = 0
    private var hold = false

    init(_ response: MailReadResult) { self.response = response }

    var reads: Int { lock.withLock { readCount } }
    var arrived: Bool { reads > 0 }

    func setResponse(_ response: MailReadResult, hold: Bool = false) {
        lock.withLock {
            self.response = response
            self.hold = hold
        }
    }

    func read() -> MailReadResult {
        let shouldHold = lock.withLock { () -> Bool in
            readCount += 1
            return hold
        }
        if shouldHold { _ = semaphore.wait(timeout: .now() + 5) }
        return lock.withLock { response }
    }

    func open() { semaphore.signal() }

    func waitForArrival() async throws {
        for _ in 0..<400 where !arrived {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(arrived, "The Mail read never started")
    }
}

/// Holds a detached Mail task before it reaches the reader's permission boundary.
final class HeldMailReadStart: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var holding = false
    private var arrived = false

    func holdNext() {
        lock.withLock {
            holding = true
            arrived = false
        }
    }

    func wait() {
        let shouldHold = lock.withLock { () -> Bool in
            guard holding else { return false }
            arrived = true
            return true
        }
        if shouldHold { _ = semaphore.wait(timeout: .now() + 5) }
    }

    func open() { semaphore.signal() }

    func waitForArrival() async throws {
        for _ in 0..<400 {
            if lock.withLock({ arrived }) { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("The queued Mail task never reached the start gate")
    }
}
@MainActor
extension OpenLoopsStoreTests {
    func testMailOptOutNeverCallsTheResponseSourceAndClearsSubjectsImmediately() async throws {
        try LoopVaultFixture.populate(root)
        let mail = FakeMailResponseSource(
            .data(rows: [["message-1", "Private subject", "read status: false"]], incomplete: false))
        let scheduledAt = Date(timeIntervalSince1970: 100)
        let store = makeStore(root: root, mail: mail, now: { scheduledAt })

        await store.refresh()
        XCTAssertEqual(mail.reads, 0)
        XCTAssertEqual(store.observations[.mail]?.state, .unauthorized)
        XCTAssertNil(store.observations[.mail]?.lastSuccessAt)
        XCTAssertEqual(store.observations[.local]?.state, .populated)

        store.setMailEnabled(true)
        await store.refreshMail()
        let observed = try XCTUnwrap(store.observations[.mail])
        XCTAssertEqual(observed.state, .populated)
        XCTAssertEqual(observed.value.map(\.nativeStatus), ["read status: false"])
        XCTAssertEqual(observed.value.map(\.title), ["Private subject"])
        XCTAssertEqual(observed.value.map(\.authority), [.mail])
        XCTAssertGreaterThan(observed.observedAt, scheduledAt, "Mail is timestamped at the read, not scheduling")
        XCTAssertNotNil(store.observations[.local]?.observedAt)
        XCTAssertEqual(observed.lastSuccessAt, observed.observedAt)

        store.setMailEnabled(false)
        XCTAssertEqual(store.observations[.mail]?.state, .unauthorized)
        XCTAssertTrue(store.observations[.mail]?.value.isEmpty == true)
        XCTAssertNil(store.observations[.mail]?.lastSuccessAt)
        XCTAssertTrue(store.loops(authority: .mail).isEmpty)
        await store.refresh()
        XCTAssertEqual(mail.reads, 1, "Opt-out must not access Mail again")
        XCTAssertEqual(store.observations[.local]?.state, .populated, "Other owners remain available")
    }

    func testOptOutBeforeQueuedMailReadStartsNeverTouchesResponseSource() async throws {
        let mail = FakeMailResponseSource(.data(rows: [["id", "Private", "read status: false"]], incomplete: false))
        let gate = HeldMailReadStart()
        gate.holdNext()
        let store = makeStore(root: nil, mailEnabled: true, mail: mail, beforeMailRead: { gate.wait() })

        let pending = Task { await store.refreshMail() }
        try await gate.waitForArrival()
        store.setMailEnabled(false)
        gate.open()
        await pending.value

        XCTAssertEqual(mail.reads, 0, "Revoking consent must stop a task queued before the reader boundary")
        XCTAssertEqual(store.observations[.mail]?.state, .unauthorized)
        XCTAssertTrue(store.loops(authority: .mail).isEmpty)
    }

    func testMailSubjectDisappearsWhilePermissionRecheckIsPending() async throws {
        let mail = FakeMailResponseSource(
            .data(rows: [["id", "Previously private", "read status: false"]], incomplete: false))
        let gate = HeldMailReadStart()
        let store = makeStore(root: nil, mailEnabled: true, mail: mail, beforeMailRead: { gate.wait() })
        await store.refreshMail()
        XCTAssertEqual(store.loops(authority: .mail).map(\.title), ["Previously private"])

        gate.holdNext()
        let pending = Task { await store.refreshMail() }
        try await gate.waitForArrival()
        XCTAssertNil(store.observations[.mail], "Do not retain the last successful Mail observation during a recheck")
        XCTAssertTrue(store.loops(authority: .mail).isEmpty)
        gate.open()
        await pending.value
        XCTAssertEqual(store.loops(authority: .mail).map(\.title), ["Previously private"])
    }

    func testMailRevocationAndUnavailableDoNotRetainPreviouslyReadSubjects() async {
        let mail = FakeMailResponseSource(
            .data(rows: [["message-1", "Sensitive", "flagged status: true"]], incomplete: false))
        let store = makeStore(root: nil, mailEnabled: true, mail: mail)
        await store.refreshMail()
        XCTAssertEqual(store.loops(authority: .mail).map(\.title), ["Sensitive"])

        mail.setResponse(.unauthorized)
        await store.refreshMail()
        XCTAssertEqual(store.observations[.mail]?.state, .unauthorized)
        XCTAssertEqual(store.observations[.mail]?.value.count, 0)
        XCTAssertNil(store.observations[.mail]?.lastSuccessAt)
        XCTAssertTrue(store.loops(authority: .mail).isEmpty)

        mail.setResponse(.unavailable)
        await store.refreshMail()
        XCTAssertEqual(store.observations[.mail]?.state, .unavailable(reason: "Mail could not be read."))
        XCTAssertEqual(store.observations[.mail]?.value.count, 0)
        XCTAssertNil(store.observations[.mail]?.lastSuccessAt)
        XCTAssertEqual(store.observations[.local]?.state, .populated)
    }

    func testDisablingMailDuringReadDiscardsItsResponseWithoutDiscardingLocalTasks() async throws {
        try LoopVaultFixture.populate(root)
        let mail = FakeMailResponseSource(
            .data(rows: [["message-1", "In-flight subject", "read status: false"]], incomplete: false))
        mail.setResponse(
            .data(rows: [["message-1", "In-flight subject", "read status: false"]], incomplete: false), hold: true)
        let store = makeStore(root: root, mailEnabled: true, mail: mail)
        let pending = Task { await store.refresh() }
        try await mail.waitForArrival()
        store.setMailEnabled(false)
        XCTAssertTrue(store.loops(authority: .mail).isEmpty)
        XCTAssertNil(store.observations[.mail]?.lastSuccessAt)
        mail.open()
        await pending.value
        XCTAssertEqual(store.observations[.mail]?.state, .unauthorized)
        XCTAssertTrue(store.loops(authority: .mail).isEmpty)
        XCTAssertEqual(store.observations[.local]?.state, .populated)
    }

    func testVaultSwitchDuringMailReadDiscardsOldResponse() async throws {
        let newRoot = try makeTemporaryVault(self)
        let mail = FakeMailResponseSource(.unavailable)
        mail.setResponse(.data(rows: [["message-1", "Old read", "read status: false"]], incomplete: false), hold: true)
        let store = makeStore(root: root, mailEnabled: true, mail: mail)
        let pending = Task { await store.refreshMail() }
        try await mail.waitForArrival()
        store.setVaultRoot(newRoot)
        mail.open()
        await pending.value

        XCTAssertNil(store.observations[.mail])
        XCTAssertTrue(store.loops(authority: .mail).isEmpty)
    }
}
