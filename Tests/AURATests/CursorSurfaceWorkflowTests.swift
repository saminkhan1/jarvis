import XCTest

final class CursorSurfaceWorkflowTests: XCTestCase {
    func testMissionStoreDoesNotForceCollapseDuringMissionLifecycle() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Stores/AURAStore.swift", encoding: .utf8)
        XCTAssertFalse(
            source.contains("cursorSurface.collapseToCompact()"),
            "AURAStore should not auto-collapse the cursor surface during mission start, cancel, or completion."
        )
    }

    func testCursorSurfaceViewExposesStateSpecificActions() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Views/CursorSurfaceView.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("case .completed, .failed, .cancelled:\n                resultCard"),
            "CursorSurfaceView should render a dedicated result state after Hermes finishes, fails, or is cancelled."
        )
        XCTAssertTrue(
            source.contains("Button(\"Cancel\")"),
            "CursorSurfaceView should expose a Cancel button while Hermes is running."
        )
        XCTAssertTrue(
            source.contains("Button(\"Done\")"),
            "CursorSurfaceView should expose a Done button to return completed output to idle state."
        )
        XCTAssertTrue(
            source.contains("store.dismissMissionResult()"),
            "Done should route through dismissMissionResult()."
        )
        XCTAssertFalse(
            source.contains("The composer collapses while Hermes works."),
            "CursorSurfaceView should not claim that the composer auto-collapses anymore."
        )
    }
}
