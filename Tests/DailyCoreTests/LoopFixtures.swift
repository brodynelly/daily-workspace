import Foundation
import XCTest

@testable import DailyCore

/// A synthetic vault in a temporary folder. No real notes.
final class FixtureVault {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func write(_ path: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func folder(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    func setModified(_ path: String, _ date: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: root.appendingPathComponent(path).path)
    }

    func link(_ path: String, to destination: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
    }
}

let fixtureNow = Date(timeIntervalSince1970: 1_800_000_000)

var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}
