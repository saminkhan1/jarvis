import XCTest

final class CursorSurfaceWorkflowTests: XCTestCase {
    func testMissionStoreDoesNotForceCollapseDuringMissionLifecycle() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Stores/AURAStore.swift", encoding: .utf8)
        guard let startRange = source.range(of: "func startMission() async"),
              let blockRange = source.range(of: "private func blockAmbientEntryPoint()") else {
            XCTFail("Could not locate mission lifecycle source.")
            return
        }
        let lifecycleSource = String(source[startRange.lowerBound..<blockRange.lowerBound])
        XCTAssertFalse(
            lifecycleSource.contains("cursorSurface.collapseToCompact()"),
            "AURAStore should not auto-collapse the cursor surface during mission start, cancel, or completion."
        )
    }

    func testMissionStartDelegatesToConcurrentSessionManager() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Stores/AURAStore.swift", encoding: .utf8)
        guard let startRange = source.range(of: "func startMission() async"),
              let cancelRange = source.range(of: "func cancelMission()") else {
            XCTFail("Could not locate mission start source.")
            return
        }

        let startSource = String(source[startRange.lowerBound..<cancelRange.lowerBound])
        XCTAssertTrue(
            startSource.contains("sessionManager.spawnSession("),
            "Starting a mission should create an independent MissionSession."
        )
        XCTAssertTrue(
            startSource.contains("missionGoal = \"\""),
            "Starting a mission should clear the composer for the next request."
        )
        XCTAssertFalse(
            startSource.contains("guard missionStatus != .running"),
            "A running mission must not block another session from starting."
        )
    }

    func testCursorSurfaceViewExposesStateSpecificActions() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Views/CursorSurfaceView.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("sessionOutputBody(session: selectedSession)"),
            "CursorSurfaceView should render selected session output without replacing the new-request composer."
        )
        XCTAssertTrue(
            source.contains("Button(\"Cancel\""),
            "CursorSurfaceView should expose a Cancel button while Hermes is running."
        )
        XCTAssertTrue(
            source.contains("accessibilityLabel(\"Minimize AURA\")"),
            "CursorSurfaceView should expose an Escape-wired minimize control."
        )
        XCTAssertTrue(
            source.contains("Button(\"Done\")"),
            "CursorSurfaceView should expose a Done button to return completed output to idle state."
        )
        XCTAssertTrue(
            source.contains("sessionManager.removeSession(selectedSession.id)"),
            "Done should remove the selected session."
        )
        XCTAssertTrue(
            source.contains("SessionPill"),
            "CursorSurfaceView should expose session pills for concurrent sessions."
        )
        XCTAssertFalse(
            source.contains("The composer collapses while Hermes works."),
            "CursorSurfaceView should not claim that the composer auto-collapses anymore."
        )
        XCTAssertFalse(
            source.contains("Close AURA cursor surface"),
            "CursorSurfaceView should not expose a second close/hide concept."
        )
        XCTAssertFalse(
            source.contains("compactActionButtons"),
            "The minimized cursor surface should stay passive and button-free."
        )
    }

    func testCompactCursorSurfaceIsPassiveForEveryState() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Services/CursorSurfaceController.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("private var shouldIgnoreMouseEvents: Bool {\n        !presentation.isComposerOpen\n    }"),
            "Minimized panels should ignore mouse events in every state."
        )
        XCTAssertTrue(
            source.contains("private var shouldTrackCompactPanel: Bool {\n        !presentation.isComposerOpen\n    }"),
            "Minimized panels should keep following the cursor in every state."
        )
        XCTAssertFalse(
            source.contains("usesInteractiveCompactPanel"),
            "The compact surface should not have actionable minimized states."
        )
    }

    func testOpeningComposerDoesNotOverwriteMissionResults() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Stores/AURAStore.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("if missionStatus == .idle"),
            "Instructional cursor-composer output should only be injected in the idle state."
        )
        XCTAssertFalse(
            source.contains("if missionStatus != .running"),
            "Opening the composer from completed, failed, or cancelled states must not overwrite result output."
        )
    }

    func testVoiceTranscriptionPausesBeforeHermesStarts() throws {
        let storeSource = try String(contentsOfFile: "Sources/AURA/Stores/AURAStore.swift", encoding: .utf8)
        guard let finishRange = storeSource.range(of: "private func finishVoiceInputAndTranscribe"),
              let meterRange = storeSource.range(of: "private func startVoiceMeter") else {
            XCTFail("Could not locate voice transcription source.")
            return
        }
        let transcriptionSource = String(storeSource[finishRange.lowerBound..<meterRange.lowerBound])

        XCTAssertTrue(
            transcriptionSource.contains("missionGoal = transcript"),
            "The editable mission goal should become the voice transcript."
        )
        XCTAssertTrue(
            transcriptionSource.contains("voiceInputState = .ready"),
            "Voice transcription should pause in the transcript-ready state."
        )
        XCTAssertFalse(
            transcriptionSource.contains("await startMission()"),
            "Voice transcription must not auto-start Hermes."
        )
        XCTAssertFalse(
            storeSource.contains("voiceInputTranscript"),
            "Voice transcript text should not be duplicated outside missionGoal."
        )
    }

    func testVoiceReadyActionsAreSendAndRetry() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Views/CursorSurfaceView.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("TextEditor(text: $store.missionGoal)"),
            "The voice transcript should be editable before sending."
        )
        XCTAssertTrue(
            source.contains("Button(\"Send\")"),
            "The ready voice transcript should expose Send."
        )
        XCTAssertTrue(
            source.contains("Button(\"Retry\")"),
            "Voice recording and ready states should expose Retry."
        )
        XCTAssertFalse(
            source.contains("Button(\"Redo\")"),
            "Voice recording should not use Redo, which conflicts with OS undo/redo meaning."
        )
        XCTAssertTrue(
            source.contains("Task { await store.redoVoiceInput() }"),
            "Retry should route through the store so it can discard and immediately restart recording."
        )
    }

    func testTextStartIsOnlyRenderedWhenStartable() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Views/CursorSurfaceView.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("private var shouldShowTextStartButton: Bool"),
            "Text Start visibility should be explicit."
        )
        XCTAssertTrue(
            source.contains("store.inputMode == .text\n            && store.canStartMission"),
            "Start should render for startable text input even while another session is running."
        )
    }

    func testMenuBarExtraUsesWindowStyleForDataRichCompanionPanel() throws {
        let source = try String(contentsOfFile: "Sources/AURA/App/AURAApp.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains(".menuBarExtraStyle(.window)"),
            "AURA's data-rich menu bar companion panel should use SwiftUI MenuBarExtra window style."
        )
    }

}
