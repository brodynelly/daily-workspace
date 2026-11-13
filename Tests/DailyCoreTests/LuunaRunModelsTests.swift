import Foundation
import Testing

@testable import DailyCore

struct LuunaRunModelsTests {
    @Test func nativeRunsKeepTheirOwnStateAndTicketOwnership() throws {
        let data = Data(
            """
            [{"id":"workflow-1","project_id":"daily-workspace","state":"completed","revision":3,"metadata":{"kind":"workflow","ticket_id":"ticket-9"},"created_at":"2026-11-13T10:00:00Z"},{"id":"baseline-2","project_id":"daily-workspace","state":"new-native-state","metadata":{"kind":"baseline"}}]
            """.utf8)
        let runs = try JSONDecoder().decode([LuunaRunRecord].self, from: data)
        #expect(runs[0].id == "workflow-1")
        #expect(runs[0].state.rawValue == "completed")
        #expect(runs[0].ticketID == "ticket-9")
        #expect(runs[0].ticketID != runs[0].id)
        #expect(runs[1].state.rawValue == "new-native-state")
        #expect(runs[1].ticketID == nil)
        let detail = try JSONDecoder().decode(
            LuunaRunRecord.self,
            from: Data(
                #"{"id":"workflow-1","project_id":"daily-workspace","state":"completed","metadata":{"ticket_id":"ticket-9"}}"#
                    .utf8))
        #expect(detail.ticketID == "ticket-9")
        // Completion belongs to the run; no ticket status is decoded or inferred.
        #expect(detail.state.rawValue == "completed")
    }

    @Test func partialLinesAndReconnectDoNotRepeatEvents() {
        var stream = LuunaRunEventStream()
        let first = stream.append(Data("{".utf8))
        #expect(first.events.isEmpty)
        #expect(stream.cursor == 0)
        let second = stream.append(Data("\"sequence\":1,\"kind\":\"started\"}\n{\"sequence\":2".utf8))
        #expect(second.events.map(\.sequence) == [1])
        #expect(stream.cursor == 1)
        #expect(stream.finish() == Data("{\"sequence\":2".utf8))
        var resumed = LuunaRunEventStream(after: stream.cursor)
        let result = resumed.append(
            Data("{\"sequence\":1}\n{\"sequence\":2,\"kind\":\"completed\"}\n{\"sequence\":2}\n".utf8))
        #expect(result.events.map(\.sequence) == [2])
        #expect(resumed.cursor == 2)
        #expect(result.events[0].fields["kind"]?.stringValue == "completed")
    }

    @Test func malformedCompleteLineDoesNotAdvanceCursor() {
        var stream = LuunaRunEventStream(after: 4)
        let result = stream.append(Data("{\"sequence\":5\n{\"sequence\":4}\n{\"sequence\":6}\n".utf8))
        #expect(result.invalidLines.count == 1)
        #expect(result.events.map(\.sequence) == [6])
        #expect(stream.cursor == 6)
    }
}
