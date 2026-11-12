import Foundation
import XCTest

@testable import DailyCore

private let utc: Calendar = MomentFormat.gregorianCalendar(timeZone: TimeZone(identifier: "UTC")!)
private let format = MomentFormat(calendar: utc)

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
}

private func assertInvalidTemplate(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
    guard case .invalidTemplate = error as? VaultError else { return XCTFail("\(error)", file: file, line: line) }
}

/// 2026-11-12 is a Thursday.
private let thursday = date(2026, 11, 12, 14, 5, 9)

final class MomentFormatTests: XCTestCase {
    func testObsidianVaultFormat() throws {
        XCTAssertEqual(
            try format.string("YYYY/MM-MMM/YYYY-MM-DD-dddd", for: thursday), "2026/11-Nov/2026-11-12-Thursday")
        XCTAssertEqual(
            try format.notePath(folder: "250-daily", format: "YYYY/MM-MMM/YYYY-MM-DD-dddd", for: thursday),
            "250-daily/2026/11-Nov/2026-11-12-Thursday.md")
    }

    func testEverySupportedToken() throws {
        let tokens = MomentFormat.supportedTokens.joined(separator: " ")
        XCTAssertEqual(
            try format.string(tokens, for: thursday),
            "2026 26 4 11 11 Nov November 12 12 12th 4 Th Thu Thursday 14 14 2 02 5 05 9 09 PM pm")
        XCTAssertEqual(
            try format.string("Q M D h hh H HH m s A a d dd", for: date(2026, 1, 4, 0, 7, 3)),
            "1 1 4 12 12 0 00 7 3 AM am 0 Su")
    }

    func testCompoundHourTokens() throws {
        XCTAssertEqual(try format.string("Hmm hmmss", for: thursday), "1405 20509")
    }

    func testMonthTokensDoNotCorruptEachOther() throws {
        XCTAssertEqual(try format.string("MM-MMM", for: thursday), "11-Nov")
        XCTAssertEqual(try format.string("MMMM", for: thursday), "November")
        XCTAssertEqual(try format.string("MMMMM", for: thursday), "November11", "Moment reads MMMM then M")
        XCTAssertEqual(try format.string("DD-dddd", for: date(2026, 2, 3)), "03-Tuesday")
    }

    func testOrdinals() throws {
        let days = [1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 11: "11th", 12: "12th", 13: "13th", 21: "21st", 22: "22nd"]
        for (day, expected) in days {
            XCTAssertEqual(try format.string("Do", for: date(2026, 1, day)), expected)
        }
    }

    func testLiteralEscapes() throws {
        XCTAssertEqual(try format.string("[Week of] YYYY", for: thursday), "Week of 2026")
        XCTAssertEqual(try format.string("YYYY-[MM]-DD", for: thursday), "2026-MM-12")
        XCTAssertEqual(try format.string("[a]b]", for: thursday), "a]b", "Moment's bracket match is greedy")
        XCTAssertEqual(try format.string("[]YYYY", for: thursday), "2026")
        XCTAssertEqual(try format.string("\\YYYY \\MMM", for: thursday), "YYYY MMM")
        XCTAssertEqual(try format.string("[pi", for: thursday), "[pi", "An unclosed bracket is plain text")
    }

    func testNonTokenLettersPassThroughAsInMoment() throws {
        XCTAssertEqual(try format.string("YYYY-MM-DDTHH:mm", for: thursday), "2026-11-12T14:05")
        XCTAssertEqual(try format.string("jour", for: thursday), "jour")
        XCTAssertEqual(try format.string("g G", for: thursday), "g G")
    }

    func testUnsupportedMomentTokensAreRefused() {
        for unsupported in [
            "YYYY-ww", "DDD", "DDDD", "L", "ll", "X", "x", "Mo", "Y", "gggg", "k", "Z", "SSS", "Qo", "E",
        ] {
            XCTAssertThrowsError(try format.string(unsupported, for: thursday), unsupported) {
                assertInvalidTemplate($0)
            }
        }
        XCTAssertNoThrow(try format.string("[ww DDD L]", for: thursday), "Escaped, they are plain text")
    }

    func testPathRefusesTraversalAndEmptySegments() {
        let refused: [(folder: String, format: String)] = [
            ("", "[..]/YYYY"), ("", "YYYY/../DD"), ("", "YYYY//MM"), ("", "YYYY/"), ("", "/YYYY"), ("../x", "YYYY"),
            ("a//b", "YYYY"), ("a/./b", "YYYY"), ("", "[.obsidian]/YYYY"), ("", "HH:mm"), ("", "[ ]"),
        ]
        for (folder, pattern) in refused {
            XCTAssertThrowsError(
                try format.notePath(folder: folder, format: pattern, for: thursday), "\(folder) + \(pattern)"
            ) { assertInvalidTemplate($0) }
        }
    }

    func testFolderEdgeSlashesAreIgnoredAndExtensionAddedOnce() throws {
        XCTAssertEqual(
            try format.notePath(folder: " /250-daily/ ", format: "YYYY-MM-DD", for: thursday), "250-daily/2026-11-12.md"
        )
        XCTAssertEqual(try format.notePath(folder: "", format: "YYYY[.md]", for: thursday), "2026.md")
    }

    func testCalendarAndLocaleAreInjected() throws {
        let tokyo = MomentFormat(
            calendar: MomentFormat.gregorianCalendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!))
        XCTAssertEqual(try tokyo.string("YYYY-MM-DD HH", for: date(2026, 3, 8, 23, 30)), "2026-03-09 08")
        let french = MomentFormat(calendar: utc, locale: Locale(identifier: "fr_FR"))
        XCTAssertEqual(try french.string("dddd D MMMM", for: thursday), "jeudi 12 novembre")
    }
}

final class ObsidianDailyNotesTests: XCTestCase {
    private var root: URL!
    private var vault: NoteVault!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        vault = NoteVault(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeConfig(_ json: String) throws {
        let url = root.appendingPathComponent(".obsidian/daily-notes.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    private func vaultFiles() -> [String] {
        let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects ?? []
        return items.compactMap { ($0 as? URL).flatMap { vault.relativePath(of: $0) } }.sorted()
    }

    func testParsesTheVaultSettings() throws {
        let settings = try ObsidianDailyNotes(
            json: Data(
                #"{"folder": "250-daily", "format": "YYYY/MM-MMM/YYYY-MM-DD-dddd", "template": "templates/daily-note"}"#
                    .utf8))
        XCTAssertEqual(settings.folder, "250-daily")
        XCTAssertEqual(settings.format, "YYYY/MM-MMM/YYYY-MM-DD-dddd")
        XCTAssertEqual(settings.templatePath, "templates/daily-note.md")
        XCTAssertEqual(
            try settings.notePath(for: thursday, formatter: format), "250-daily/2026/11-Nov/2026-11-12-Thursday.md")
    }

    func testMissingKeysTakeObsidianDefaults() throws {
        XCTAssertEqual(try ObsidianDailyNotes(json: Data("{}".utf8)), ObsidianDailyNotes())
        XCTAssertEqual(try ObsidianDailyNotes(json: Data()), ObsidianDailyNotes())
        let partial = try ObsidianDailyNotes(json: Data(#"{"folder": " Daily ", "format": "", "autorun": true}"#.utf8))
        XCTAssertEqual(partial, ObsidianDailyNotes(folder: "Daily", format: "YYYY-MM-DD", template: ""))
        XCTAssertNil(partial.templatePath)
        XCTAssertEqual(
            try ObsidianDailyNotes(json: Data(#"{"folder": 3}"#.utf8)).folder, "", "Wrong type counts as missing")
        XCTAssertEqual(ObsidianDailyNotes(template: "/t/daily.md").templatePath, "t/daily.md")
    }

    func testDamagedSettingsAreRefused() {
        XCTAssertThrowsError(try ObsidianDailyNotes(json: Data("not json".utf8)))
        XCTAssertThrowsError(try ObsidianDailyNotes(json: Data("[1]".utf8)))
    }

    func testLoadReadsTheVaultFileOrReportsNone() throws {
        XCTAssertNil(try ObsidianDailyNotes.load(from: vault))
        try writeConfig(#"{"folder": "250-daily"}"#)
        XCTAssertEqual(try ObsidianDailyNotes.load(from: vault)?.folder, "250-daily")
        XCTAssertEqual(vaultFiles(), [".obsidian", ".obsidian/daily-notes.json"], "Reading writes nothing")
    }

    func testTemplateVariables() {
        let body = """
            date: "{{date:YYYY-MM-DD}}"
            # {{date:YYYY-MM-DD-dddd}} {{title}}
            [[standups/{{date:YYYY}}/{{ date : MM-MMM }}/x]] {{date}} {{time}} {{time:HH:mm:ss}} {{DATE}}
            keep {{foo}} {{date:ww}} {{date:}} {{date
            """
        let rendered = ObsidianDailyNotes.render(
            template: body, title: "2026-11-12-Thursday", date: thursday, formatter: format)
        XCTAssertEqual(
            rendered,
            """
            date: "2026-11-12"
            # 2026-11-12-Thursday 2026-11-12-Thursday
            [[standups/2026/11-Nov/x]] 2026-11-12 14:05 14:05:09 2026-11-12
            keep {{foo}} {{date:ww}} {{date:}} {{date
            """)
    }

    func testResolverUsesObsidianSettingsWhenPresent() throws {
        try writeConfig(
            #"{"folder": "250-daily", "format": "YYYY/MM-MMM/YYYY-MM-DD-dddd", "template": "templates/daily-note"}"#)
        let resolver = DailyNoteResolver(
            source: .obsidian, custom: DailyNoteTemplate(folder: "Ignored"), formatter: format)
        let resolution = try resolver.resolve(in: vault, for: thursday)
        XCTAssertEqual(resolution.path, "250-daily/2026/11-Nov/2026-11-12-Thursday.md")
        XCTAssertEqual(resolution.templatePath, "templates/daily-note.md")
        XCTAssertEqual(resolution.title, "2026-11-12-Thursday")
        guard case .obsidian = resolution.origin else { return XCTFail("\(resolution.origin)") }
    }

    func testResolverNeverPicksTheVaultRootImplicitly() throws {
        let noFolder = DailyNoteResolver(source: .obsidian, custom: DailyNoteTemplate(), formatter: format)
        XCTAssertThrowsError(try noFolder.resolve(in: vault, for: thursday)) {
            XCTAssertEqual($0 as? VaultError, .dailyNoteFolderUnset)
        }

        let fallback = DailyNoteResolver(
            source: .obsidian, custom: DailyNoteTemplate(folder: "Daily"), formatter: format)
        XCTAssertEqual(try fallback.resolve(in: vault, for: thursday).path, "Daily/2026-11-12.md")
        XCTAssertEqual(try fallback.resolve(in: vault, for: thursday).origin, .customFallback)

        let explicitRoot = DailyNoteResolver(source: .custom, custom: DailyNoteTemplate(), formatter: format)
        XCTAssertEqual(try explicitRoot.resolve(in: vault, for: thursday).path, "2026-11-12.md", "Chosen by the user")

        try writeConfig("{}")
        XCTAssertThrowsError(try noFolder.resolve(in: vault, for: thursday), "Obsidian's own root default") {
            XCTAssertEqual($0 as? VaultError, .dailyNoteFolderUnset)
        }
        XCTAssertEqual(vaultFiles(), [".obsidian", ".obsidian/daily-notes.json"])
    }

    func testResolverRefusesAnUnsupportedObsidianFormat() throws {
        try writeConfig(#"{"folder": "Daily", "format": "gggg-[W]ww"}"#)
        let resolver = DailyNoteResolver(
            source: .obsidian, custom: DailyNoteTemplate(folder: "Daily"), formatter: format)
        XCTAssertThrowsError(try resolver.resolve(in: vault, for: thursday)) {
            XCTAssertEqual(
                ($0 as? LocalizedError)?.errorDescription,
                "The daily-note template is invalid (unsupported format token “gggg”).")
        }
    }

    func testSettingsDecodeTheSourceTolerantly() throws {
        let decode = { (json: String) in try JSONDecoder().decode(WorkspaceSettings.self, from: Data(json.utf8)) }
        XCTAssertEqual(try decode("{}").dailyNoteSource, .obsidian)
        XCTAssertEqual(try decode(#"{"dailyNoteSource": "custom"}"#).dailyNoteSource, .custom)
        XCTAssertEqual(try decode(#"{"dailyNoteSource": "bogus", "dailyFolder": "D"}"#).dailyNoteSource, .obsidian)
        XCTAssertEqual(try decode(#"{"dailyNoteSource": "bogus", "dailyFolder": "D"}"#).dailyFolder, "D")
        let saved = WorkspaceSettings(dailyNoteSource: .custom)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceSettings.self, from: JSONEncoder().encode(saved)), saved)
    }
}
