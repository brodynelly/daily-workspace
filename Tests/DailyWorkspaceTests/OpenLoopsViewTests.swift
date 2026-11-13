import DailyCore
import SwiftUI
import XCTest

@testable import DailyWorkspace

final class LoopToneTests: XCTestCase {
    private func tone(_ authority: LoopAuthority, _ status: String) -> Tone {
        LoopTone.tone(authority: authority, nativeStatus: status)
    }

    func testNativeOwnerStatusesNeverTurnARunIntoATicket() {
        XCTAssertEqual(tone(.local, "open"), .attention)
        XCTAssertEqual(tone(.reminders, "incomplete"), .attention)
        XCTAssertEqual(tone(.mail, "unread"), .neutral, "Mail does not infer task status")
        XCTAssertEqual(tone(.local, "completed"), .neutral)
        XCTAssertEqual(tone(.reminders, "completed"), .neutral)
        XCTAssertEqual(tone(.luuna, "completed"), .neutral, "A completed run is not a closed ticket")
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
            loop(.local, "local-1", project: "beta"),
            loop(.local, "local-2", project: "beta", status: "completed", done: true),
            loop(.reminders, "r1", status: "incomplete"),
            loop(.mail, "m1", status: "unread"),
            loop(.luuna, "run-1", project: "alpha", status: "completed", done: true),
        ]
    }

    func testTheDefaultFilterHidesDoneItemsAndKeepsOrder() {
        let shown = OpenLoopsFilter().apply(to: loops)
        XCTAssertEqual(shown.map(\.title), ["local-1", "r1", "m1"])
        XCTAssertFalse(shown.contains { $0.isDoneInSource })
    }

    func testSourceProjectAndDoneFiltersCombine() {
        var filter = OpenLoopsFilter(source: .local)
        XCTAssertEqual(filter.apply(to: loops).map(\.title), ["local-1"])
        filter.showDone = true
        XCTAssertEqual(filter.apply(to: loops).map(\.title), ["local-1", "local-2"])
        filter.project = "beta"
        XCTAssertEqual(filter.apply(to: loops).map(\.title), ["local-1", "local-2"])
        filter = OpenLoopsFilter(source: .all, project: "alpha", showDone: true)
        XCTAssertEqual(filter.apply(to: loops).map(\.title), ["run-1"])
        XCTAssertEqual(OpenLoopsFilter(source: .mail).apply(to: loops).map(\.title), ["m1"])
    }

    func testProjectsAreOnlySlugsStatedByOwners() {
        XCTAssertEqual(OpenLoopsFilter.projects(in: loops), ["alpha", "beta"])
        XCTAssertEqual(LoopSourceFilter.allCases.map(\.title), ["All", "Local", "Reminders", "Luuna", "Mail"])
    }

    func testExternalRowsHaveNoActions() {
        XCTAssertEqual(loop(.mail, "m1").ownerActions, [])
        XCTAssertEqual(loop(.luuna, "run-1").ownerActions, [])
    }

    func testAppOwnedRowsKeepTheirOwnersActions() {
        XCTAssertEqual(loop(.local, "local-1").ownerActions, [.complete, .edit, .delete])
        XCTAssertEqual(
            loop(.local, "local-2", status: "completed", done: true).ownerActions,
            [.reopen, .edit, .delete])
        XCTAssertEqual(loop(.reminders, "r1", status: "incomplete").ownerActions, [.completeReminder])
    }

    func testDateLinesKeepTheOwningSourceText() {
        let source = "2026-11-12T09:00:00Z"
        let other = OpenLoop(
            authority: .local, nativeID: "local-1", title: "Pay rent", kind: "task", nativeStatus: "open",
            isDoneInSource: false, deadline: LoopDate(year: 2026, month: 11, day: 12, raw: source),
            observedAt: now)
        XCTAssertEqual(other.dateLines, ["Due \(source)"])
        XCTAssertEqual(other.deadline?.raw, source)
    }
}

final class ProjectDetailMarkdownTests: XCTestCase {
    func testHubPurposeAndDecisionMarkdownRenderWithFormattingAndSafeWebLinks() {
        let purpose = "**Important** [roadmap](https://example.com/plan) and [local](file:///tmp/private)"
        let rendered = ProjectDetailCard.renderMarkdown(purpose)
        XCTAssertEqual(String(rendered.characters), "Important roadmap and local")
        XCTAssertTrue(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertEqual(rendered.runs.compactMap { $0.link?.absoluteString }, ["https://example.com/plan"])

        let decision = "Keep `source` and [bad](mailto:test@example.com) unchanged"
        let shown = ProjectDetailCard.renderMarkdown(decision)
        XCTAssertEqual(String(shown.characters), "Keep source and bad unchanged")
        XCTAssertTrue(shown.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        XCTAssertFalse(shown.runs.contains { $0.link != nil })
    }
}

final class ObservedSourceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAnUnreadableSourceIsNeverNothingOpen() {
        let missing = SourceObservation<[OpenLoop]>(
            state: .unavailable(reason: "store inaccessible"), value: [], observedAt: now)
        let empty = SourceObservation<[OpenLoop]>(state: .empty, value: [], observedAt: now)
        XCTAssertEqual(
            ObservedSource("Local", observation: missing, summary: "nothing open").text,
            "Local unavailable: store inaccessible"
        )
        XCTAssertEqual(ObservedSource("Local", observation: empty, summary: "nothing open").text, "Local: nothing open")
        XCTAssertEqual(ObservedSource("Local", observation: missing, summary: "nothing open").tone, .interrupted)
        XCTAssertEqual(
            ObservedSource(
                "Reminders",
                observation: SourceObservation<[OpenLoop]>(state: .uninitialized, value: [], observedAt: now),
                summary: "", notSetUp: "not connected"
            ).text,
            "Reminders not set up: not connected")
        XCTAssertEqual(
            ObservedSource("Local", observation: SourceObservation<[OpenLoop]>?.none, summary: "").text,
            "Local: not read yet")
    }

    func testPartialAndStaleReadsSayWhenTheyWereLastRead() {
        let earlier = now.addingTimeInterval(-600)
        let partial = SourceObservation<[OpenLoop]>(
            state: .partial(issues: [SourceIssue(path: "tasks.json", line: 3, message: "bad task")]),
            value: [], observedAt: now)
        let partialStatus = ObservedSource("Local", observation: partial, summary: "2 open")
        XCTAssertEqual(partialStatus.tone, .attention)
        XCTAssertEqual(partialStatus.issues, ["tasks.json:3: bad task"])
        XCTAssertEqual(partialStatus.lastRead, now)

        let good = SourceObservation<[OpenLoop]>(state: .populated, value: [], observedAt: earlier)
        let stale = SourceObservation<[OpenLoop]>(state: .unauthorized, value: [], observedAt: now).following(good)
        let staleStatus = ObservedSource("Local", observation: stale, summary: "1 open")
        XCTAssertEqual(staleStatus.lastRead, earlier)
        XCTAssertTrue(staleStatus.text.hasPrefix("Local not authorized"), staleStatus.text)
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
