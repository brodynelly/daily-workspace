import XCTest
@testable import DailyCore

final class VaultIndexTests: XCTestCase {
    func testIndexSearchAndBacklinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Journal"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ["Journal/Today.md": "# Focus\nA unique phrase", "Wiki.md": "[[Today#Focus|alias]]", "Relative.md": "[daily](Journal/Today.md)", "Journal/Previous.md": "[next](Today.md)", "Unrelated.md": "[[Tomorrow]]", ".hidden.md": "secret"]
        for (path, text) in files { try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        let notes = try VaultIndex.scan(root: root)
        XCTAssertEqual(notes.count, 5)
        XCTAssertEqual(VaultIndex.search("TODAY unique", in: notes).map(\.path), ["Journal/Today.md"])
        XCTAssertEqual(Set(VaultIndex.backlinks(to: "Journal/Today.md", in: notes).map(\.path)), ["Wiki.md", "Relative.md", "Journal/Previous.md"])
    }

    func testSymlinkAndInvalidUTF8AreExcluded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0xff, 0xfe]).write(to: root.appendingPathComponent("bad.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside.md"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        XCTAssertTrue(try VaultIndex.scan(root: root).isEmpty)
    }
}
