import DailyCore
import SwiftUI
import XCTest

@testable import DailyWorkspace

final class LoopToneTests: XCTestCase {
    private func tone(_ authority: LoopAuthority, _ status: String) -> Tone {
        LoopTone.tone(authority: authority, nativeStatus: status)
    }

    func testAttentionIsWaitingOnBrody() {
        for status in ["TODO", "NEXT", "WAIT", "WAITING"] { XCTAssertEqual(tone(.org, status), .attention, status) }
        XCTAssertEqual(tone(.seeds, "open"), .attention)
        XCTAssertEqual(tone(.seeds, "ready"), .attention)
        XCTAssertEqual(tone(.plot, "ready"), .attention)
        XCTAssertEqual(tone(.local, "open"), .attention)
        XCTAssertEqual(tone(.reminders, "incomplete"), .attention)
    }

    func testActiveIsBeingWorkedAndDangerIsBlocked() {
        XCTAssertEqual(tone(.seeds, "in_progress"), .active)
        XCTAssertEqual(tone(.seeds, "claimed"), .active)
        XCTAssertEqual(tone(.plot, "drafting"), .active)
        XCTAssertEqual(tone(.plot, "active"), .active)
        XCTAssertEqual(tone(.seeds, "blocked"), .danger)
    }

    func testFinishedAndUnknownStatusesAreNeutral() {
        let finished: [(LoopAuthority, String)] = [
            (.org, "DONE"), (.org, "CANCELLED"), (.org, "CANCELED"), (.seeds, "closed"), (.seeds, "done"),
            (.plot, "done"), (.plot, "archived"), (.local, "completed"), (.reminders, "completed"),
        ]
        for (authority, status) in finished { XCTAssertEqual(tone(authority, status), .neutral, status) }
        for status in ["", "todo", "In Progress", "HOLD", "someday", "passed"] {
            XCTAssertEqual(tone(.org, status), .neutral, "Org \(status)")
            XCTAssertEqual(tone(.seeds, status), .neutral, "Seeds \(status)")
        }
        XCTAssertEqual(tone(.luuna, "completed"), .neutral, "A Luuna run completed is not a closed task")
    }

    func testGreenIsNeverGivenToAnyStatus() {
        let statuses = [
            "TODO", "NEXT", "WAIT", "DONE", "CANCELLED", "open", "ready", "in_progress", "claimed", "blocked", "closed",
            "done", "completed", "passed", "success", "drafting", "active", "archived", "incomplete", "approved",
        ]
        for authority in LoopAuthority.allCases {
            for status in statuses {
                XCTAssertNotEqual(tone(authority, status), .success, "\(authority) \(status)")
            }
        }
    }
}

final class OpenLoopsFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func loop(
        _ authority: LoopAuthority, _ id: String, project: String? = nil, status: String = "open", done: Bool = false,
        path: String? = nil
    ) -> OpenLoop {
        OpenLoop(
            authority: authority, nativeID: id, title: id, kind: "task", project: project, nativeStatus: status,
            isDoneInSource: done, sourcePath: path, observedAt: now)
    }

    private var loops: [OpenLoop] {
        [
            loop(.org, "o1", status: "TODO", path: "org/inbox.org"),
            loop(.org, "o2", status: "DONE", done: true, path: "org/inbox.org"),
            loop(.seeds, "s1", project: "alpha", path: ".seeds/issues.jsonl"),
            loop(.seeds, "s2", project: "beta", status: "closed", done: true, path: ".seeds/issues.jsonl"),
            loop(.plot, "p1", project: "alpha", status: "drafting", path: ".plot/p1.json"),
            loop(.local, UUID().uuidString),
            loop(.reminders, "r1", status: "incomplete"),
        ]
    }

    func testTheDefaultFilterHidesDoneItemsAndKeepsOrder() {
        let shown = OpenLoopsFilter().apply(to: loops)
        XCTAssertEqual(shown.map(\.title).prefix(3), ["o1", "s1", "p1"])
        XCTAssertFalse(shown.contains { $0.isDoneInSource })
        XCTAssertEqual(shown.count, 5)
    }

    func testSourceProjectAndDoneFiltersCombine() {
        var filter = OpenLoopsFilter(source: .seeds)
        XCTAssertEqual(filter.apply(to: loops).map(\.title), ["s1"])
        filter.showDone = true
        XCTAssertEqual(filter.apply(to: loops).map(\.title), ["s1", "s2"])
        filter.project = "beta"
        XCTAssertEqual(filter.apply(to: loops).map(\.title), ["s2"])
        filter = OpenLoopsFilter(source: .all, project: "alpha")
        XCTAssertEqual(filter.apply(to: loops).map(\.title), ["s1", "p1"])
        XCTAssertEqual(OpenLoopsFilter(source: .reminders).apply(to: loops).map(\.title), ["r1"])
        XCTAssertEqual(OpenLoopsFilter(source: .org, showDone: true).apply(to: loops).map(\.title), ["o1", "o2"])
    }

    func testProjectsAreTheSlugsOwnersState() {
        XCTAssertEqual(OpenLoopsFilter.projects(in: loops), ["alpha", "beta"])
        XCTAssertEqual(LoopSourceFilter.allCases.map(\.title), ["All", "Local", "Org", "Seeds", "Plot", "Reminders"])
    }

    func testExternalRowsOnlyOpenTheirSource() {
        for loop in loops where [.org, .seeds, .plot].contains(loop.authority) {
            XCTAssertEqual(loop.ownerActions, [.openSource], loop.id)
            XCTAssertFalse(loop.ownerActions.contains { $0.writes }, "No write action on \(loop.id)")
        }
        let unlocated = loop(.seeds, "s9")
        XCTAssertEqual(unlocated.ownerActions, [], "Nothing to open without a source path")
    }

    func testAppOwnedRowsKeepTheirOwnersActions() {
        XCTAssertEqual(loop(.local, UUID().uuidString).ownerActions, [.complete, .edit, .delete])
        XCTAssertEqual(
            loop(.local, UUID().uuidString, status: "completed", done: true).ownerActions, [.reopen, .edit, .delete])
        XCTAssertEqual(loop(.reminders, "r1", status: "incomplete").ownerActions, [.completeReminder])
        XCTAssertEqual(loop(.luuna, "l1").ownerActions, [])
    }

    func testRowsShowGeneratedIdsAndVerbatimDates() {
        XCTAssertEqual(loop(.seeds, "brain-a1").displayedID, "brain-a1")
        XCTAssertNil(loop(.org, "abc").displayedID)
        let dated = OpenLoop(
            authority: .org, nativeID: "x", title: "x", kind: "heading", nativeStatus: "TODO", isDoneInSource: false,
            scheduled: LoopDate(year: 2026, month: 11, day: 12, raw: "<2026-11-12 Thu>"),
            deadline: LoopDate(year: 2026, month: 11, day: 20, raw: "<2026-11-20 Fri>"), sourcePath: "org/inbox.org",
            line: 4, observedAt: now)
        XCTAssertEqual(dated.dateLines, ["Scheduled <2026-11-12 Thu>", "Deadline <2026-11-20 Fri>"])
        XCTAssertEqual(dated.sourceLocation, "org/inbox.org:4")
    }
}

final class ObservedSourceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAnUnreadableSourceIsNeverNothingOpen() {
        let missing = SourceObservation<[OpenLoop]>(
            state: .unavailable(reason: "no org/ folder"), value: [], observedAt: now)
        let empty = SourceObservation<[OpenLoop]>(state: .empty, value: [], observedAt: now)
        XCTAssertEqual(
            ObservedSource("Org", observation: missing, summary: "nothing open").text, "Org unavailable: no org/ folder"
        )
        XCTAssertEqual(ObservedSource("Org", observation: empty, summary: "nothing open").text, "Org: nothing open")
        XCTAssertEqual(ObservedSource("Org", observation: missing, summary: "nothing open").tone, .interrupted)
        XCTAssertEqual(
            ObservedSource(
                "Seeds", observation: SourceObservation<[OpenLoop]>(state: .uninitialized, value: [], observedAt: now),
                summary: "", notSetUp: "no .seeds/ folder"
            ).text,
            "Seeds not set up: no .seeds/ folder")
        XCTAssertEqual(
            ObservedSource("Org", observation: SourceObservation<[OpenLoop]>?.none, summary: "").text,
            "Org: not read yet")
    }

    func testPartialAndStaleReadsSayWhenTheyWereLastRead() {
        let earlier = now.addingTimeInterval(-600)
        let partial = SourceObservation<[OpenLoop]>(
            state: .partial(issues: [SourceIssue(path: ".seeds/issues.jsonl", line: 3, message: "not JSON")]),
            value: [], observedAt: now)
        let partialStatus = ObservedSource("Seeds", observation: partial, summary: "2 open")
        XCTAssertEqual(partialStatus.tone, .attention)
        XCTAssertEqual(partialStatus.issues, [".seeds/issues.jsonl:3: not JSON"])
        XCTAssertEqual(partialStatus.lastRead, now)

        let good = SourceObservation<[OpenLoop]>(state: .populated, value: [], observedAt: earlier)
        let stale = SourceObservation<[OpenLoop]>(state: .unauthorized, value: [], observedAt: now).following(good)
        let staleStatus = ObservedSource("Org", observation: stale, summary: "1 open")
        XCTAssertEqual(staleStatus.lastRead, earlier)
        XCTAssertTrue(staleStatus.text.hasPrefix("Org not authorized"), staleStatus.text)
        XCTAssertTrue(staleStatus.text.hasSuffix("Showing the last read"), staleStatus.text)
    }
}

@MainActor
final class ProjectsAndLuunaViewTests: XCTestCase {
    func testTheRestartSectionRendersInsideAProject() {
        let model = AppModel(dependencies: .test())
        let section = ProjectRestartSection(slug: "daily-workspace")
        XCTAssertEqual(section.slug, "daily-workspace")
        XCTAssertNotNil(ImageRenderer(content: section.workspaceEnvironment(model).frame(width: 600)).nsImage)
    }

    func testLuunaSettingsRefuseANonLoopbackOriginBeforeSaving() throws {
        let keys = FakeKeyStore()
        let model = AppModel(dependencies: .test(luunaKeys: keys))

        let refusal = LuunaSettingsView.connect(model, origin: "http://example.com:4242", token: "secret")

        XCTAssertEqual(refusal, "Use an HTTP loopback runtime URL (127.0.0.1, localhost or [::1]).")
        XCTAssertNil(try keys.read(), "No token is stored for a refused origin")
        XCTAssertEqual(model.luuna.origin, .standard)
        XCTAssertFalse(model.luuna.hasToken)
        XCTAssertEqual(LuunaSettingsView.connect(model, origin: "https://127.0.0.1:4242", token: ""), refusal)
        XCTAssertEqual(
            LuunaSettingsView.connect(model, origin: "http://127.0.0.1:4242/api", token: ""),
            "Runtime URL must contain only a loopback address and optional port.")

        XCTAssertNil(LuunaSettingsView.connect(model, origin: "http://localhost:4300", token: " tok "))
        XCTAssertEqual(try keys.read(), "tok")
        XCTAssertEqual(model.luuna.origin.description, "http://localhost:4300")
    }

    func testOnlyALiveAuthenticatedConnectionIsGreen() async {
        let reader = FakeLuunaReader()
        let luuna = LuunaStore(reader: reader, token: "tok")
        XCTAssertNotEqual(LuunaStatusWords.connection(luuna).tone, .success)
        await luuna.refresh()
        XCTAssertEqual(LuunaStatusWords.connection(luuna).tone, .success)
        XCTAssertEqual(LuunaStatusWords.connection(luuna).text, "Connected to http://127.0.0.1:4242")

        reader.set("projects", Result<[LuunaProjectRecord], LuunaReadFailure>.failure(.unauthorized))
        await luuna.refresh()
        XCTAssertEqual(LuunaStatusWords.connection(luuna).tone, .attention)
        XCTAssertTrue(LuunaStatusWords.connection(luuna).text.hasPrefix("Not connected"))
    }
}
