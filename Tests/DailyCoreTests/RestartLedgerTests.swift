import XCTest

@testable import DailyCore

final class RestartLedgerTests: XCTestCase {
    private var folder: URL!
    private var ledger: RestartLedger!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString)")
        ledger = RestartLedger(url: folder.appendingPathComponent("app/restart-ledger.jsonl"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func record(_ project: String, accepted: TimeInterval, decision: String = "Ship it.") -> RestartRecord {
        RestartRecord(
            projectSlug: project, createdAt: Date(timeIntervalSince1970: accepted - 60),
            acceptedAt: Date(timeIntervalSince1970: accepted + 0.5), decision: decision,
            nextAction: "Write the \"release\" note.\nThen tag.", notes: "n",
            sources: [
                SourceRef(
                    path: "01-projects/a/hub.md", sha256: String(repeating: "a", count: 64),
                    observedAt: Date(timeIntervalSince1970: accepted - 30.5))
            ])
    }

    func testAppendedRecordsReadBackPerProjectInOrder() throws {
        let first = record("alpha", accepted: 1_800_000_000)
        let other = record("beta", accepted: 1_800_000_100)
        let second = record("alpha", accepted: 1_800_000_200, decision: "Pause.")
        for item in [first, other, second] { try ledger.append(item) }

        let read = try ledger.records(project: "alpha")
        XCTAssertEqual(read.records, [first, second])
        XCTAssertEqual(read.skippedLines, [])
        XCTAssertEqual(read.latest, second)
        XCTAssertEqual(try ledger.allRecords().records.count, 3)

        let lines = try String(contentsOf: ledger.url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains(#""project":"alpha""#))
        XCTAssertTrue(lines[0].contains(#""next_action":"#))
    }

    func testTheLedgerIsPrivateToThisUser() throws {
        try ledger.append(record("alpha", accepted: 1_800_000_000))
        let attributes = try FileManager.default.attributesOfItem(atPath: ledger.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptLinesAreSkippedReportedAndNeverRewritten() throws {
        let good = record("alpha", accepted: 1_800_000_000)
        try ledger.append(good)
        let handle = try FileHandle(forWritingTo: ledger.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n{\"project\":\"alpha\",\"partial".utf8))
        try handle.close()
        let damaged = try Data(contentsOf: ledger.url)

        var read = try ledger.records(project: "alpha")
        XCTAssertEqual(read.records, [good])
        XCTAssertEqual(read.skippedLines, [2, 3])
        XCTAssertEqual(try Data(contentsOf: ledger.url), damaged)

        let later = record("alpha", accepted: 1_800_000_500)
        try ledger.append(later)
        let after = try Data(contentsOf: ledger.url)
        XCTAssertEqual(after.prefix(damaged.count), damaged)
        read = try ledger.records(project: "alpha")
        XCTAssertEqual(read.records, [good, later])
        XCTAssertEqual(read.skippedLines, [2, 3])
    }

    func testAMissingLedgerReadsAsEmpty() throws {
        let read = try ledger.records(project: "alpha")
        XCTAssertEqual(read.records, [])
        XCTAssertNil(read.latest)
    }

    func testARecordNeedsAProject() {
        XCTAssertThrowsError(try ledger.append(record("  ", accepted: 1))) { error in
            XCTAssertEqual(error as? RestartLedgerError, .emptyProject)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: ledger.url.path))
    }

    func testSHA256OfBytesAndFiles() throws {
        XCTAssertEqual(
            RestartLedger.sha256(of: Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let file = folder.appendingPathComponent("note.md")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try RestartLedger.sha256(ofFileAt: file), RestartLedger.sha256(of: Data("abc".utf8)))
    }

    func testLedgerLivesInTheAppFolder() {
        let directory = WorkspaceDirectory(url: URL(fileURLWithPath: "/tmp/home/.config/daily-workspace"))
        XCTAssertEqual(directory.restartLedgerURL.path, "/tmp/home/.config/daily-workspace/restart-ledger.jsonl")
    }
}
