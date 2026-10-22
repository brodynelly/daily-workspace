import XCTest
@testable import DailyCore

final class SpringTests: XCTestCase {
    func testSpringConvergesWithoutOvershoot() {
        var s = CriticallyDampedSpring(position: 100, velocity: 0)
        var previous = s.position
        for _ in 0..<600 {
            s.update(dt: 1.0 / 120.0, length: 0.15)
            XCTAssertGreaterThanOrEqual(s.position, 0, "critical damping must not overshoot")
            XCTAssertLessThanOrEqual(s.position, previous + 1e-9)
            previous = s.position
        }
        XCTAssertTrue(s.isSettled)
    }

    func testSpringIsStableForHugeFrameTime() {
        var s = CriticallyDampedSpring(position: 50, velocity: 10)
        s.update(dt: 5, length: 0.15)
        XCTAssertTrue(s.isSettled)
    }

    func testSpringResultIndependentOfStepSize() {
        var coarse = CriticallyDampedSpring(position: 80, velocity: 0)
        var fine = CriticallyDampedSpring(position: 80, velocity: 0)
        coarse.update(dt: 0.05, length: 0.3)
        for _ in 0..<50 { fine.update(dt: 0.001, length: 0.3) }
        XCTAssertEqual(coarse.position, fine.position, accuracy: 0.05)
    }
}

final class CaretAnimatorTests: XCTestCase {
    private let a = CaretRect(x: 10, y: 10, width: 2, height: 18)

    func testFirstMoveSnaps() {
        var animator = CaretAnimator(config: CaretPreset.comet.config)
        animator.moveTo(a, cellWidth: 8)
        XCTAssertFalse(animator.isAnimating)
        XCTAssertEqual(animator.quad.first, CaretPoint(x: 10, y: 10))
    }

    func testReachesDestination() {
        for preset in CaretPreset.allCases where preset != .off {
            var animator = CaretAnimator(config: preset.config)
            animator.moveTo(a, cellWidth: 8)
            let b = CaretRect(x: 300, y: 80, width: 2, height: 18)
            animator.moveTo(b, cellWidth: 8)
            XCTAssertTrue(animator.isAnimating)
            for _ in 0..<600 { animator.step(dt: 1.0 / 60.0) }
            XCTAssertFalse(animator.isAnimating, "\(preset)")
            XCTAssertEqual(animator.quad[0], CaretPoint(x: 300, y: 80), "\(preset)")
            XCTAssertEqual(animator.quad[2], CaretPoint(x: 302, y: 98), "\(preset)")
        }
    }

    func testTrailStretchesOnLongJump() {
        var animator = CaretAnimator(config: CaretPreset.comet.config)
        animator.moveTo(a, cellWidth: 8)
        animator.moveTo(CaretRect(x: 400, y: 10, width: 2, height: 18), cellWidth: 8)
        animator.step(dt: 1.0 / 60.0)
        let q = animator.quad
        // Moving right: the right-hand corners lead, the left-hand corners trail behind.
        XCTAssertGreaterThan(q[1].x, q[0].x + 20)
    }

    func testTypingUsesShortAnimation() {
        var animator = CaretAnimator(config: CaretPreset.glide.config)
        animator.moveTo(a, cellWidth: 8)
        animator.moveTo(CaretRect(x: 18, y: 10, width: 2, height: 18), cellWidth: 8)
        for _ in 0..<12 { animator.step(dt: 1.0 / 60.0) } // 0.2 s > short length 0.09 s
        XCTAssertFalse(animator.isAnimating)
    }

    func testImmediateMoveSnaps() {
        var animator = CaretAnimator(config: CaretPreset.comet.config)
        animator.moveTo(a, cellWidth: 8)
        animator.moveTo(CaretRect(x: 200, y: 200, width: 2, height: 18), cellWidth: 8, immediate: true)
        XCTAssertFalse(animator.isAnimating)
        XCTAssertEqual(animator.quad[0], CaretPoint(x: 200, y: 200))
    }
}

final class TemplateTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func testDefaultTemplate() throws {
        let path = try DailyNoteTemplate().relativePath(for: date(2026, 10, 22), calendar: utc)
        XCTAssertEqual(path, "2026-10-22.md")
    }

    func testFolderAndTokens() throws {
        let t = DailyNoteTemplate(folder: "Daily/YYYY/MM", filename: "DD - Journal")
        XCTAssertEqual(try t.relativePath(for: date(2026, 1, 5), calendar: utc), "Daily/2026/01/05 - Journal.md")
    }

    func testRejectsTraversal() {
        XCTAssertThrowsError(try DailyNoteTemplate(folder: "../outside").relativePath(for: Date()))
        XCTAssertThrowsError(try DailyNoteTemplate(filename: "..").relativePath(for: Date()))
        XCTAssertThrowsError(try DailyNoteTemplate(filename: "a/b").relativePath(for: Date()))
        XCTAssertThrowsError(try DailyNoteTemplate(filename: "  ").relativePath(for: Date()))
    }

    func testNoDoubleExtension() throws {
        let t = DailyNoteTemplate(filename: "YYYY-MM-DD.md")
        XCTAssertEqual(try t.relativePath(for: date(2026, 10, 22), calendar: utc), "2026-10-22.md")
    }

    func testDayBoundaryUsesProvidedCalendar() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var comps = DateComponents(); comps.year = 2026; comps.month = 3; comps.day = 8; comps.hour = 23; comps.minute = 30
        comps.timeZone = TimeZone(identifier: "UTC")
        let instant = Calendar(identifier: .gregorian).date(from: comps)! // 23:30 UTC = 08:30 next day in Tokyo
        XCTAssertEqual(try DailyNoteTemplate().relativePath(for: instant, calendar: tokyo), "2026-03-09.md")
    }
}

final class VaultTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testCreateLoadSaveRoundTripPreservesUnknownContent() throws {
        let vault = NoteVault(root: dir)
        let url = try vault.resolve(relativePath: "Daily/2026-10-22.md")
        let original = "---\ntags: [a]\n---\r\n# Title\r\n[[Wiki Link]] ![[embed.png]] **bold** 日本語 🎉\r\n"
        _ = try vault.create(url, initialText: original)

        let loaded = try vault.load(url)
        XCTAssertEqual(loaded.text, original, "bytes including CRLF and unicode must survive")

        let saved = try vault.save(loaded.text + "- new\n", to: url, expecting: loaded.snapshot)
        let reloaded = try vault.load(url)
        XCTAssertEqual(reloaded.text, original + "- new\n")
        XCTAssertEqual(reloaded.snapshot, saved)
    }

    func testExternalEditIsDetectedAndNotOverwritten() throws {
        let vault = NoteVault(root: dir)
        let url = try vault.resolve(relativePath: "n.md")
        _ = try vault.create(url, initialText: "one\n")
        let loaded = try vault.load(url)

        try Data("changed elsewhere\n".utf8).write(to: url)

        XCTAssertThrowsError(try vault.save("mine\n", to: url, expecting: loaded.snapshot)) {
            XCTAssertEqual($0 as? VaultError, .conflict)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "changed elsewhere\n")
    }

    func testTouchWithoutContentChangeIsNotAConflict() throws {
        let vault = NoteVault(root: dir)
        let url = try vault.resolve(relativePath: "n.md")
        _ = try vault.create(url, initialText: "same\n")
        let loaded = try vault.load(url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(100)], ofItemAtPath: url.path)
        XCTAssertNoThrow(try vault.save("same\nmore\n", to: url, expecting: loaded.snapshot))
    }

    func testDeletedFileIsReportedMissing() throws {
        let vault = NoteVault(root: dir)
        let url = try vault.resolve(relativePath: "n.md")
        _ = try vault.create(url, initialText: "x")
        let loaded = try vault.load(url)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try vault.save("y", to: url, expecting: loaded.snapshot)) {
            XCTAssertEqual($0 as? VaultError, .missing)
        }
    }

    func testCreateNeverReplacesExistingNote() throws {
        let vault = NoteVault(root: dir)
        let url = try vault.resolve(relativePath: "n.md")
        _ = try vault.create(url, initialText: "keep me")
        XCTAssertThrowsError(try vault.create(url, initialText: "clobber")) {
            XCTAssertEqual($0 as? VaultError, .alreadyExists)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "keep me")
    }

    func testInvalidUTF8IsRefusedNotRewritten() throws {
        let vault = NoteVault(root: dir)
        let url = dir.appendingPathComponent("bin.md")
        try Data([0xff, 0xfe, 0x00, 0x41]).write(to: url)
        XCTAssertThrowsError(try vault.load(url)) { XCTAssertEqual($0 as? VaultError, .notUTF8) }
    }

    func testPathsCannotEscapeVault() {
        let vault = NoteVault(root: dir)
        XCTAssertThrowsError(try vault.resolve(relativePath: "../evil.md"))
        XCTAssertThrowsError(try vault.resolve(relativePath: "a/../../evil.md"))
        XCTAssertNoThrow(try vault.resolve(relativePath: "a/../ok.md"))
    }
}

final class TaskTests: XCTestCase {
    func testAddCompleteReopenRemoveRestore() {
        var list = TaskList()
        let day = LocalDay(year: 2026, month: 10, day: 22)
        let t = list.add(title: "  Write spec  ", due: day)!
        XCTAssertEqual(t.title, "Write spec")
        XCTAssertNil(list.add(title: "   "))

        XCTAssertEqual(list.dueToday(day).count, 1)
        list.complete(id: t.id)
        XCTAssertEqual(list.dueToday(day).count, 0)
        XCTAssertEqual(list.completed.count, 1)
        list.reopen(id: t.id)
        XCTAssertEqual(list.dueToday(day).count, 1)

        let removed = list.remove(id: t.id)!
        XCTAssertTrue(list.items.isEmpty)
        list.restore(removed)
        XCTAssertEqual(list.items.count, 1)
        list.restore(removed)
        XCTAssertEqual(list.items.count, 1, "restore is idempotent")
    }

    func testOverdueStaysInToday_AndFutureDoesNot() {
        var list = TaskList()
        let today = LocalDay(year: 2026, month: 10, day: 22)
        list.add(title: "old", due: LocalDay(year: 2026, month: 10, day: 1))
        list.add(title: "later", due: LocalDay(year: 2026, month: 10, day: 30))
        list.add(title: "someday")
        XCTAssertEqual(list.dueToday(today).map(\.title), ["old"])
        XCTAssertEqual(list.upcoming(after: today).map(\.title), ["later"])
        XCTAssertEqual(list.inbox.map(\.title), ["someday"])
    }

    func testPersistenceRoundTripAndCorruptFileIsKeptAside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskPersistence(url: dir.appendingPathComponent("tasks.json"))

        var list = TaskList()
        list.add(title: "persist me", due: LocalDay(year: 2026, month: 10, day: 22))
        try store.save(list)
        XCTAssertEqual(try store.load().items.map(\.title), ["persist me"])

        try Data("{not json".utf8).write(to: store.url)
        XCTAssertTrue(try store.load().items.isEmpty)
        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("corrupt") }
        XCTAssertEqual(aside.count, 1, "corrupt data must be preserved, not deleted")
    }

    func testLocalDayOrderingAndFormat() {
        XCTAssertLessThan(LocalDay(year: 2026, month: 2, day: 28), LocalDay(year: 2026, month: 3, day: 1))
        XCTAssertEqual(LocalDay(year: 2026, month: 3, day: 5).description, "2026-03-05")
    }
}
