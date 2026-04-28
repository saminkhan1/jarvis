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

    func testHermesChatArgumentsPassRawPromptWithoutAuraMissionEnvelope() {
        let query = "what can you help me do in this repo?"

        let arguments = AURAStore.hermesChatArguments(query: query)

        XCTAssertEqual(arguments, ["chat", "-Q", "--yolo", "--source", "aura", "-q", query])
        XCTAssertFalse(arguments.joined(separator: " ").contains("AURA MISSION CONTEXT"))
    }
}
