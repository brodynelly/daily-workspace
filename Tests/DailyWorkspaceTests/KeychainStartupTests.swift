import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

private final class BlockingCredential: APIKeyStore, @unchecked Sendable {
    let started: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    private let staleToken: String
    private let lock = NSLock()
    private var stored: String?
    private var reads = 0
    var readCount: Int { lock.withLock { reads } }
    var savedToken: String? { lock.withLock { stored } }

    init(started: XCTestExpectation, token: String = "stale-token") {
        self.started = started
        staleToken = token
    }

    func read() throws -> String? {
        lock.withLock { reads += 1 }
        started.fulfill()
        release.wait()
        return staleToken
    }

    func save(_ key: String) throws {
        lock.withLock { stored = key.isEmpty ? nil : key }
    }
}

@MainActor
final class KeychainStartupTests: XCTestCase {
    func testColdStartDoesNotWaitForLuunaKeychainAndPreservesSourceState() async throws {
        let credential = BlockingCredential(started: expectation(description: "background Keychain read"))
        let directory = WorkspaceDirectory(url: try makeTemporaryVault(self))
        var dependencies = AppModel.Dependencies.test(directory: directory)
        dependencies.observesSystem = true
        dependencies.luunaKeyStore = credential
        let model = AppModel(dependencies: dependencies)
        defer { credential.release.signal() }

        await fulfillment(of: [credential.started], timeout: 2)
        XCTAssertTrue(model.luunaCredentialLoading)
        XCTAssertFalse(model.luuna.hasToken)
        XCTAssertEqual(model.luuna.health.state, .unavailable(.notChecked))

        credential.release.signal()
        try await waitUntil { !model.luunaCredentialLoading }
        XCTAssertEqual(model.luunaWorkToken, "stale-token")
        XCTAssertTrue(model.luuna.hasToken)
    }

    func testInteractiveConnectionCannotBeOverwrittenByDelayedStartupRead() async throws {
        let credential = BlockingCredential(started: expectation(description: "background Keychain read"))
        let directory = WorkspaceDirectory(url: try makeTemporaryVault(self))
        var dependencies = AppModel.Dependencies.test(directory: directory)
        dependencies.observesSystem = true
        dependencies.luunaKeyStore = credential
        let model = AppModel(dependencies: dependencies)
        defer { credential.release.signal() }

        await fulfillment(of: [credential.started], timeout: 2)
        XCTAssertNil(model.connectLuuna(origin: LuunaOrigin.standard.description, token: "current-token"))
        XCTAssertEqual(credential.savedToken, "current-token")
        XCTAssertFalse(model.luunaCredentialLoading)
        credential.release.signal()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.luunaWorkToken, "current-token")
        XCTAssertTrue(model.luuna.hasToken)
    }

    func testAssistantCredentialReadStartsOnlyWhenShown() async {
        let credential = BlockingCredential(started: expectation(description: "explicit Assistant key read"))
        let key = AssistantKey(
            store: credential, backgroundReads: true, deferInitialRead: true, openRouterStore: credential)
        defer { credential.release.signal() }
        key.setProvider(.openRouter)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(credential.readCount, 0)
        XCTAssertTrue(key.isChecking)

        key.refresh()
        await fulfillment(of: [credential.started], timeout: 2)
        XCTAssertEqual(credential.readCount, 1)
        credential.release.signal()
        do {
            try await waitUntil { !key.isChecking }
        } catch { XCTFail("Explicit Assistant key check did not finish") }
        XCTAssertTrue(key.isSaved)
    }

    func testAssistantKeyShowsCheckingInsteadOfNotSetDuringBlockedRead() async {
        let credential = BlockingCredential(started: expectation(description: "background Assistant key read"))
        let key = AssistantKey(store: credential, backgroundReads: true)
        defer { credential.release.signal() }
        await fulfillment(of: [credential.started], timeout: 2)
        XCTAssertTrue(key.isChecking)
        XCTAssertFalse(key.isSaved)
        XCTAssertNil(key.readError)
        credential.release.signal()
        do {
            try await waitUntil { !key.isChecking }
        } catch { XCTFail("Assistant key remained in the checking state") }
        XCTAssertTrue(key.isSaved)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Credential read did not return within two seconds")
    }
}
