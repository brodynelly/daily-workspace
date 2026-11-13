import DailyCore
import Foundation
import XCTest

@testable import DailyWorkspace

@MainActor
extension AssistantGoldenSetTests {

    private func note(_ path: String, _ fact: String) -> Lookup {
        Lookup(
            name: "read_note", input: "{\"path\":\"\(path)\",\"max_bytes\":20000}", evidence: [fact],
            citation: .init(kind: .path, value: path))
    }

    private func project(_ facts: String...) -> Lookup {
        Lookup(
            name: "get_project", input: #"{"slug":"atlas"}"#,
            evidence: [#""hub_path":"01-projects/atlas/atlas.md""#] + facts,
            citation: .init(kind: .path, value: Self.hub))
    }

    private func excluded(_ path: String) -> Lookup {
        Lookup(
            name: "read_note", input: "{\"path\":\"\(path)\",\"max_bytes\":20000}",
            evidence: ["excluded"], citation: nil, isError: true)
    }

    private func goldenQuestions() -> [Question] {
        let excludedPaths = [
            "04-archive/old.md", "templates/template.md", "00-inbox/automation/generated.md",
            "00-inbox/remarkable/raw.md", "_private/secret.md", "01-projects/atlas/index-board.md",
            "01-projects/nested/notes.md",
        ]
        let base = [
            Question(
                id: 1, text: "What is the Atlas outline about?",
                lookups: [project("Index synthetic field observations")],
                answer: "Atlas indexes synthetic field observations (\(Self.hub))."),
            Question(
                id: 2, text: "What is the next restart action?",
                lookups: [note(Self.state, "Inspect the indexing tests before editing the mapper")],
                answer: "Inspect the indexing tests before editing the mapper (\(Self.state))."),
            Question(
                id: 3, text: "Was the receipt filed?",
                lookups: [note(Self.restart, "context only; not a current ticket")],
                answer: "The checklist is historical context, not proof of a current action (\(Self.restart))."),
            Question(
                id: 4, text: "Is the Atlas outline a current ticket?",
                lookups: [project("Index synthetic field observations")],
                answer: "The project hub is context, not a current ticket (\(Self.hub))."),
            Question(
                id: 5, text: "Is feedback review finished?",
                lookups: [project("Keep the index local")],
                answer: "The hub records a decision, not a completed action (\(Self.hub))."),
            Question(
                id: 6, text: "Did the completed run finish the outline?",
                lookups: [note(Self.run, "returned `completed`"), project("Index synthetic field observations")],
                answer: "The run completed (\(Self.run)); the hub does not establish an outline status (\(Self.hub))."),
            Question(
                id: 7, text: "What is Atlas for?", lookups: [project("Index synthetic field observations")],
                answer: "Atlas indexes synthetic field observations (\(Self.hub))."),
            Question(
                id: 8, text: "What did Atlas decide?", lookups: [project("Keep the index local")],
                answer: "Keep the index local until review (\(Self.hub))."),
            Question(
                id: 9, text: "What exactly should I do on restart?",
                lookups: [note(Self.state, "Inspect the indexing tests before editing the mapper")],
                answer: "Inspect the indexing tests before editing the mapper (\(Self.state))."),
            Question(
                id: 10, text: "What sources did the accepted restart use?",
                lookups: [project(Self.hubHash, Self.restartHash)],
                answer: "Accepted record \(Self.recordID.uuidString) cites \(Self.hub) and \(Self.restart)."),
            Question(
                id: 11, text: "Is the unchecked Markdown checklist a current ticket?",
                lookups: [note(Self.restart, "context only; not a current ticket")],
                answer: "No: it is historical context, not a current ticket (\(Self.restart))."),
        ]
        let exclusions = excludedPaths.enumerated().map { offset, path in
            Question(
                id: offset + 12, text: "Read \(path) for me.", lookups: [excluded(path)],
                answer: "I can't read \(path): that path is excluded.")
        }
        return base + exclusions + [
            Question(
                id: 19, text: "Does the unchecked restart checklist create a current action?",
                lookups: [note(Self.restart, "context only; not a current ticket")],
                answer: "No: the old checklist remains context only (\(Self.restart)); it is not a current action."),
            Question(
                id: 20, text: "Is my agenda empty today?",
                lookups: [
                    Lookup(
                        name: "get_agenda", input: #"{"day":"2026-11-12"}"#,
                        evidence: ["unavailable", "unknown, not empty"], citation: nil, isError: true)
                ],
                answer: "Calendar is unavailable, so the agenda is unknown, not empty."),
        ]
    }

    private func prepareLedger(at appRoot: URL) throws {
        let ledger = RestartLedger(url: WorkspaceDirectory(url: appRoot).restartLedgerURL)
        let earlierAcceptance = AssistantTestClock.now.addingTimeInterval(-86_400)
        let olderRecord = RestartRecord(
            id: Self.olderRecordID, projectSlug: "atlas", createdAt: earlierAcceptance,
            acceptedAt: earlierAcceptance, decision: "Review the synthetic run.",
            nextAction: "Read the run note.",
            sources: [SourceRef(path: Self.run, sha256: Self.runHash, observedAt: earlierAcceptance)])
        let record = RestartRecord(
            id: Self.recordID, projectSlug: "atlas", createdAt: AssistantTestClock.now,
            acceptedAt: AssistantTestClock.now, decision: "Keep the index local until review.",
            nextAction: "Inspect the indexing tests before editing the mapper.",
            sources: [
                SourceRef(path: Self.hub, sha256: Self.hubHash, observedAt: AssistantTestClock.now),
                SourceRef(path: Self.restart, sha256: Self.restartHash, observedAt: AssistantTestClock.now),
            ])
        try ledger.append(record)
        // Append the older acceptance last so file order cannot stand in for acceptance time.
        try ledger.append(olderRecord)
        XCTAssertEqual(
            try ledger.records(project: "atlas").records.map(\.id),
            [Self.recordID, Self.olderRecordID])
    }

    private func assertOpenLoopFixture(_ context: WorkspaceAssistantContext) async throws {
        let unreadable = await context.unreadableLoopSources()
        XCTAssertNil(unreadable["org"])
        XCTAssertNil(unreadable["mail"])
        let allLoops = try await context.openLoops(source: nil, project: nil, status: nil)
        XCTAssertFalse(allLoops.contains { $0.title == "published index" }, "Historical checkboxes are not tasks")
        XCTAssertFalse(allLoops.contains { $0.source == "org" })
        do {
            _ = try await context.openLoops(source: "org", project: nil, status: nil)
            XCTFail("Retired source must be rejected")
        } catch let failure as ToolFailure {
            XCTAssertTrue(failure.message.contains("There is no source"))
        }
    }

    private func assertRestartSources(_ content: String, turn: AssistantTurn) throws {
        let payload = try XCTUnwrap(parseJSONObject(Data(content.utf8)))
        let restart = try XCTUnwrap(payload["latest_restart"] as? [String: Any])
        let sources = try XCTUnwrap(restart["sources"] as? [[String: Any]])
        XCTAssertEqual(restart["project"] as? String, "atlas")
        XCTAssertEqual(
            restart["accepted_at"] as? String,
            ISO8601DateFormatter().string(from: AssistantTestClock.now))
        XCTAssertEqual(restart["decision"] as? String, "Keep the index local until review.")
        XCTAssertEqual(
            restart["next_action"] as? String,
            "Inspect the indexing tests before editing the mapper.")
        XCTAssertEqual(sources.count, 2)
        XCTAssertTrue(sources.allSatisfy { ($0["observed_at"] as? String)?.contains("2026-11-12") == true })
        let pairs = sources.compactMap { source -> (String, String)? in
            guard let path = source["path"] as? String, let hash = source["sha256"] as? String else {
                return nil
            }
            return (path, hash)
        }
        let observed = Dictionary(pairs, uniquingKeysWith: { _, last in last })
        XCTAssertEqual(observed, [Self.hub: Self.hubHash, Self.restart: Self.restartHash])
        XCTAssertEqual(restart["id"] as? String, Self.recordID.uuidString)
        XCTAssertNotEqual(restart["id"] as? String, Self.olderRecordID.uuidString)
        XCTAssertTrue(turn.citations.contains(.init(kind: .record, value: Self.recordID.uuidString)))
    }

    func testTwentyGoldenQuestionsAgainstVaultAndToolLoop() async throws {
        let root = try makeTemporaryVault(self)
        try copyFixture(into: root)
        let appRoot = try makeTemporaryVault(self)
        try prepareLedger(at: appRoot)
        let calendar = FakeCalendarStore()
        calendar.authorization = .unavailable
        let model = try await model(root: root, appRoot: appRoot, calendar: calendar)
        let context = model.assistantContext
        try await assertOpenLoopFixture(context)
        let questions = goldenQuestions()
        XCTAssertEqual(questions.map(\.id), Array(1...20))

        let keys = FakeKeyStore()
        keys.key = "synthetic-key-never-sent-over-network"
        for question in questions {
            let uses = question.lookups.enumerated().map { offset, lookup in
                toolCall("gold_\(question.id)_\(offset)", lookup.name, lookup.input)
            }
            let transport = FakeAgentTransport([
                .success(agentResponse(uses, stop: "tool_use")),
                .success(agentResponse([.text(question.answer)], stop: "end_turn")),
            ])
            let session = AssistantSession(
                transport: transport, keyStore: keys, context: context,
                configuration: AssistantTestClock.configuration, isEnabled: true)
            session.send(question.text)
            await session.waitForCompletion()
            XCTAssertNil(session.error, "Q\(question.id)")
            XCTAssertEqual(transport.requests.count, 2, "Q\(question.id) must complete a real tool round")
            let turn = try XCTUnwrap(session.turns.first, "Q\(question.id)")
            XCTAssertEqual(turn.answer, question.answer, "Q\(question.id)")
            XCTAssertEqual(turn.toolCalls.count, question.lookups.count, "Q\(question.id)")
            let results = try XCTUnwrap(transport.requests.dropFirst().first?.messages.last?.content)
            XCTAssertEqual(results.count, question.lookups.count, "Q\(question.id)")
            for (offset, lookup) in question.lookups.enumerated() {
                let result = try XCTUnwrap(results.indices.contains(offset) ? results[offset] : nil)
                let block = try XCTUnwrap(parseJSONObject(result))
                let content = try XCTUnwrap(block["content"] as? String)
                XCTAssertEqual(block["tool_use_id"] as? String, "gold_\(question.id)_\(offset)")
                XCTAssertEqual(block["is_error"] as? Bool == true, lookup.isError, "Q\(question.id)")
                for fact in lookup.evidence {
                    XCTAssertTrue(content.contains(fact), "Q\(question.id): missing \(fact) in \(content)")
                }
                if let row = lookup.row {
                    let payload = try XCTUnwrap(parseJSONObject(Data(content.utf8)))
                    let rows = try XCTUnwrap(payload["rows"] as? [[String: Any]])
                    let found = try XCTUnwrap(rows.first { $0["title"] as? String == row.title })
                    XCTAssertEqual(found["source"] as? String, row.source, "Q\(question.id)")
                    XCTAssertEqual(found["status"] as? String, row.status, "Q\(question.id)")
                    XCTAssertEqual(found["id"] as? String, lookup.citation?.value, "Q\(question.id)")
                    if question.id == 2 {
                        XCTAssertEqual(found["deadline"] as? String, "<2026-11-20 Fri>")
                    }
                    XCTAssertTrue(
                        turn.answer.contains(row.status),
                        "Q\(question.id): answer must keep the owner's native status")
                }
                if let citation = lookup.citation {
                    XCTAssertTrue(turn.citations.contains(citation), "Q\(question.id): missing \(citation)")
                    XCTAssertTrue(
                        turn.answer.contains(citation.value), "Q\(question.id): answer must cite its evidence")
                } else {
                    let call = try XCTUnwrap(turn.toolCalls.indices.contains(offset) ? turn.toolCalls[offset] : nil)
                    XCTAssertTrue(call.citations.isEmpty, "Q\(question.id)")
                }
                XCTAssertFalse(content.contains("PRIVATE_"), "Q\(question.id): excluded text leaked")
                if question.id == 10 {
                    try assertRestartSources(content, turn: turn)
                }
            }
            let secondBody = try XCTUnwrap(transport.bodies.dropFirst().first)
            XCTAssertFalse(secondBody.description.contains("PRIVATE_"), "Q\(question.id): private text sent")
            if (12...18).contains(question.id) {
                XCTAssertTrue(turn.toolCalls.first?.isError == true, "Q\(question.id): path was not refused")
            }
        }
    }
}
