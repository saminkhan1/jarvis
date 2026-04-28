import XCTest
@testable import AURA

final class HermesBoundaryTests: XCTestCase {
    func testMergedEnvironmentInjectsAuraMetadataAndPreservesCustomEnvironment() {
        let merged = HermesService.mergedEnvironmentForTesting([
            "FOO": "bar",
            "AURA_PROCESS_KIND": "user-value-should-not-win"
        ], traceID: "trace-123")

        XCTAssertEqual(merged["FOO"], "bar")
        XCTAssertEqual(merged["AURA_TRACE_ID"], "trace-123")
        XCTAssertEqual(merged["AURA_PROCESS_KIND"], "hermes")
        XCTAssertEqual(merged["AURA_SKIP_WRAPPER_EXEC_TELEMETRY"], "1")
        XCTAssertNotNil(merged["AURA_APP_SESSION_ID"])
        XCTAssertNotNil(merged["AURA_PARENT_PID"])
        XCTAssertNotNil(merged["AURA_AUDIT_LEDGER_PATH"])
    }

    func testExtractSessionIDReturnsTrimmedValueFromOutput() {
        let output = """
        some prelude
        session_id: abc-123  
        trailing
        """

        XCTAssertEqual(AURASessionParsing.sessionID(in: output), "abc-123")
    }

    func testExtractSessionIDReturnsNilWhenMissing() {
        XCTAssertNil(AURASessionParsing.sessionID(in: "no session marker here"))
    }

    func testSessionSummariesDecodeHermesExportAndPreferUserGoalPreview() {
        let older = #"{"id":"older","source":"aura","started_at":1700000000,"last_active":1700000010,"ended_at":1700000010,"message_count":4,"messages":[{"role":"user","content":"AURA MISSION CONTEXT\n\nUSER GOAL\nTell me more about this.\n\nCURRENT MAC CONTEXT\n- Active app: Finder"}]}"#
        let newer = #"{"id":"newer","source":"aura","started_at":1700000100,"last_active":1700000200,"ended_at":1700000200,"message_count":2,"messages":[{"role":"user","content":"inspect script/setup.sh and summarize its responsibilities"}]}"#
        let ignored = #"{"id":"ignored-cli","source":"cli","started_at":1700000300,"last_active":1700000400,"ended_at":1700000400,"message_count":1,"messages":[{"role":"user","content":"should not appear"}]}"#
        let export = [older, newer, ignored].joined(separator: "\n")

        let result = AURASessionParsing.sessionSummaries(in: export, source: "aura", limit: 8)
        let summaries = result.summaries

        XCTAssertEqual(result.malformedRecordCount, 0)
        XCTAssertEqual(summaries.map(\.id), ["newer", "older"])
        XCTAssertEqual(summaries.first?.preview, "inspect script/setup.sh and summarize its responsibilities")
        XCTAssertEqual(summaries.last?.preview, "Tell me more about this.")
        XCTAssertEqual(summaries.last?.messageCount, 4)
    }

    func testSessionSummariesLimitResultsAndFallBackToSessionIdentifierPreview() {
        let export = [
            #"{"id":"one","source":"aura","started_at":1,"last_active":3,"ended_at":3,"message_count":0,"messages":[]}"#,
            #"{"id":"two","source":"aura","started_at":1,"last_active":2,"ended_at":2,"message_count":0,"messages":[]}"#
        ].joined(separator: "\n")

        let result = AURASessionParsing.sessionSummaries(in: export, source: "aura", limit: 1)
        let summaries = result.summaries

        XCTAssertEqual(result.malformedRecordCount, 0)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.id, "one")
        XCTAssertEqual(summaries.first?.preview, "Session one")
    }

    func testSessionSummariesReportMalformedExportRecords() {
        let export = [
            #"{"id":"valid","source":"aura","started_at":1,"last_active":3,"ended_at":3,"message_count":1,"messages":[{"role":"user","content":"hello"}]}"#,
            "{not-json}"
        ].joined(separator: "\n")

        let result = AURASessionParsing.sessionSummaries(in: export, source: "aura", limit: 8)

        XCTAssertEqual(result.malformedRecordCount, 1)
        XCTAssertEqual(result.summaries.count, 1)
        XCTAssertEqual(result.summaries.first?.id, "valid")
    }

    func testHermesChatArgumentsPassRawPromptWithoutAuraMissionEnvelope() {
        let query = "what can you help me do in this repo?"

        let arguments = AURAStore.hermesChatArguments(query: query)

        XCTAssertEqual(arguments, ["chat", "-Q", "--yolo", "--source", "aura", "-q", query])
        XCTAssertFalse(arguments.joined(separator: " ").contains("AURA MISSION CONTEXT"))
    }
}
