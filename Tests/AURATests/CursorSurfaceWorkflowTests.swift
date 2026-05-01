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
        XCTAssertFalse(
            lifecycleSource.contains("cursorSurface.closeBubblePanel()"),
            "AURAStore should not auto-close the cursor bubble during mission start, cancel, or completion."
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

    func testCursorSurfaceViewUsesClickyBubbleInputAndOutput() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Views/CursorSurfaceView.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("sessionBubble(session)"),
            "CursorSurfaceView should render mission state through the Clicky-style cursor bubble."
        )
        XCTAssertTrue(
            source.contains("Text(\"...\")"),
            "CursorSurfaceView should use Clicky's ellipsis placeholder."
        )
        XCTAssertTrue(
            source.contains("Working on"),
            "Running missions should acknowledge the submitted request instead of returning to an empty composer."
        )
        XCTAssertTrue(
            source.contains("accessibilityLabel(\"Cancel running request\")"),
            "Running missions should expose a compact cancel affordance in the cursor bubble."
        )
        XCTAssertTrue(
            source.contains("arrow.up.circle.fill"),
            "Text input should expose a visible Clicky-style send affordance."
        )
        XCTAssertTrue(
            source.contains("ClickyBubbleBackground"),
            "CursorSurfaceView should use Clicky's rounded response-bubble background."
        )
        XCTAssertTrue(
            source.contains("ScrollView(.vertical)"),
            "Mission output should be scrollable inside the cursor bubble."
        )
        XCTAssertTrue(
            source.contains(".textSelection(.enabled)"),
            "Mission output text should be selectable."
        )
        XCTAssertTrue(
            source.contains(".onExitCommand(perform: minimizeSurface)"),
            "CursorSurfaceView should keep Escape wired to collapse the bubble."
        )
        XCTAssertFalse(
            source.contains("SessionPill"),
            "The cursor surface should not keep the legacy session-strip UI."
        )
        XCTAssertFalse(
            source.contains("Button(\"Cancel\""),
            "The Clicky-style output bubble should not keep legacy cursor-surface action buttons."
        )
        XCTAssertFalse(
            source.contains("Button(\"Done\""),
            "The Clicky-style output bubble should not keep legacy cursor-surface action buttons."
        )
        XCTAssertFalse(
            source.contains("AURAVisualStyle"),
            "The cursor surface should use Clicky's local bubble styling, not the old Aura card styling."
        )
    }

    func testCursorSurfaceControllerHasNoLegacyCompactPanel() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Services/CursorSurfaceController.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("private var bubbleAnchorTopLeft: NSPoint?"),
            "The cursor bubble should pin to an opening anchor instead of chasing the mouse."
        )
        XCTAssertTrue(
            source.contains("cursor.x + 22"),
            "The cursor bubble should still open with Clicky's response-overlay horizontal cursor offset."
        )
        XCTAssertTrue(
            source.contains("cursor.y - 6 - size.height"),
            "The cursor bubble should still open with Clicky's response-overlay vertical cursor offset."
        )
        XCTAssertTrue(
            source.contains("window.ignoresMouseEvents = false"),
            "The cursor bubble must receive mouse events so users can scroll, select text, and press controls."
        )
        XCTAssertTrue(
            source.contains("hideCursorOverlay()"),
            "The decorative cursor overlay should be hidden while an interactive bubble is open."
        )
        XCTAssertFalse(
            source.contains("panelTrackingTimer"),
            "The interactive cursor bubble should not keep a timer that follows the mouse."
        )
        XCTAssertFalse(
            source.contains("shouldIgnoreBubbleMouseEvents"),
            "Finished output must not ignore mouse events."
        )
        XCTAssertFalse(
            source.contains("CursorSurfaceSizing"),
            "The legacy compact badge sizing helper should be removed."
        )
        XCTAssertFalse(
            source.contains("compactPanelSize"),
            "The legacy compact badge size state should be removed."
        )
        XCTAssertFalse(
            source.contains("updateCompactTracking"),
            "The old compact-panel tracking path should be removed."
        )
    }

    func testCursorSurfaceEscapeIsHandledAtPanelLevel() throws {
        let controllerSource = try String(contentsOfFile: "Sources/AURA/Services/CursorSurfaceController.swift", encoding: .utf8)
        let storeSource = try String(contentsOfFile: "Sources/AURA/Stores/AURAStore.swift", encoding: .utf8)

        XCTAssertTrue(
            controllerSource.contains("private var escapeKeyMonitor: Any?"),
            "Escape dismissal should not depend only on SwiftUI's onExitCommand."
        )
        XCTAssertTrue(
            controllerSource.contains("NSEvent.addLocalMonitorForEvents(matching: .keyDown)"),
            "The cursor surface should monitor Escape while the composer is open, including while TextEditor has focus."
        )
        XCTAssertTrue(
            controllerSource.contains("event.keyCode == UInt16(kVK_Escape)"),
            "The local key monitor should target Escape specifically."
        )
        XCTAssertTrue(
            controllerSource.contains("override func cancelOperation"),
            "The panel should handle AppKit cancelOperation for Escape routed through the responder chain."
        )
        XCTAssertTrue(
            controllerSource.contains("override func keyDown(with event: NSEvent)"),
            "The panel should fall back to direct keyDown handling when Escape reaches the window."
        )
        XCTAssertTrue(
            controllerSource.contains("stopEscapeKeyMonitor()"),
            "The local Escape monitor should be removed when the composer closes or hides."
        )
        XCTAssertTrue(
            storeSource.contains("if inputMode == .voice {\n            cancelVoiceInput()"),
            "Escape dismissal should cancel active voice input before closing the cursor surface."
        )
    }

    func testCursorSurfaceUsesClickyOverlayTreatment() throws {
        let controllerSource = try String(contentsOfFile: "Sources/AURA/Services/CursorSurfaceController.swift", encoding: .utf8)
        let overlaySource = try String(contentsOfFile: "Sources/AURA/Views/CursorSurfaceOverlayView.swift", encoding: .utf8)

        XCTAssertTrue(
            controllerSource.contains("CursorSurfaceOverlayWindow"),
            "The cursor surface should use a full-screen transparent overlay window."
        )
        XCTAssertTrue(
            controllerSource.contains("level = .screenSaver"),
            "The cursor surface should match Clicky's always-on-top overlay level."
        )
        XCTAssertTrue(
            controllerSource.contains("hostingView.setAccessibilityElement(false)"),
            "The visual-only overlay should be hidden from accessibility inspection."
        )
        XCTAssertTrue(
            overlaySource.contains(".accessibilityHidden(true)"),
            "The SwiftUI overlay content should be accessibility-hidden."
        )
        XCTAssertTrue(
            overlaySource.contains("private let fullWelcomeMessage = \"hey! i'm clicky\""),
            "The cursor surface should preserve Clicky's welcome copy."
        )
        XCTAssertTrue(
            overlaySource.contains("Color(hex: \"#3380FF\")"),
            "The cursor surface should use Clicky's blue cursor color."
        )
        XCTAssertTrue(
            overlaySource.contains("ClickyCursorTriangle"),
            "The cursor surface should render the Clicky triangle cursor."
        )
        XCTAssertTrue(
            overlaySource.contains("BlueCursorWaveformView"),
            "The cursor surface should render the Clicky listening waveform."
        )
        XCTAssertTrue(
            overlaySource.contains("BlueCursorSpinnerView"),
            "The cursor surface should render the Clicky processing spinner."
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

    func testVoiceTranscriptionAutoStartsHermesLikeClicky() throws {
        let storeSource = try String(contentsOfFile: "Sources/AURA/Stores/AURAStore.swift", encoding: .utf8)
        guard let finishRange = storeSource.range(of: "private func finishVoiceInputAndTranscribe"),
              let meterRange = storeSource.range(of: "private func startVoiceMeter") else {
            XCTFail("Could not locate voice transcription source.")
            return
        }
        let transcriptionSource = String(storeSource[finishRange.lowerBound..<meterRange.lowerBound])

        XCTAssertTrue(
            transcriptionSource.contains("missionGoal = transcript"),
            "The mission goal should become the final voice transcript before launch."
        )
        XCTAssertTrue(
            transcriptionSource.contains("if inputMode == .voice, canStartMission"),
            "Voice transcription should gate auto-start through the normal mission readiness checks."
        )
        XCTAssertFalse(
            transcriptionSource.contains("voiceInputState = .ready"),
            "Voice transcription should not keep the legacy transcript-ready stopover."
        )
        XCTAssertFalse(
            transcriptionSource.contains("Transcript ready"),
            "Voice transcription should not keep the legacy transcript review copy."
        )
        XCTAssertTrue(
            transcriptionSource.contains("await startMission()"),
            "Voice transcription should auto-start Hermes instead of keeping the legacy Send/Retry review UI."
        )
        XCTAssertFalse(
            storeSource.contains("voiceInputTranscript"),
            "Voice transcript text should not be duplicated outside missionGoal."
        )
    }

    func testVoiceSurfaceDoesNotKeepLegacyReadyActions() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Views/CursorSurfaceView.swift", encoding: .utf8)
        XCTAssertFalse(
            source.contains("Button(\"Send\")"),
            "Voice input should use the Clicky waveform/spinner flow instead of a legacy Send button."
        )
        XCTAssertFalse(
            source.contains("Button(\"Retry\")"),
            "Voice input should use the Clicky waveform/spinner flow instead of a legacy Retry button."
        )
        XCTAssertFalse(
            source.contains("Button(\"Redo\")"),
            "Voice recording should not use Redo, which conflicts with OS undo/redo meaning."
        )
    }

    func testTextInputUsesClickyBubbleWithKeyboardSubmission() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Views/CursorSurfaceView.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("TextEditor(text: $store.missionGoal)"),
            "Typed input should stay available inside the Clicky-style bubble."
        )
        XCTAssertTrue(
            source.contains("Command-Return"),
            "Typed input should show the keyboard submission affordance."
        )
        XCTAssertTrue(
            source.contains(".keyboardShortcut(.return, modifiers: [.command])"),
            "Typed input should submit with Command-Return without restoring the old Start button."
        )
        XCTAssertFalse(
            source.contains("Button(\"Start\""),
            "The old visible Start button should not be rendered in the cursor surface."
        )
    }

    func testDashboardPrioritizesMissionWorkflowBeforeDiagnostics() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Views/ContentView.swift", encoding: .utf8)
        guard let missionRunnerRange = source.range(of: "MissionRunnerView(store: store)"),
              let missionConfigRange = source.range(of: "MissionConfigurationCard(store: store)"),
              let readinessRange = source.range(of: "ReadinessCenterView(store: store)") else {
            XCTFail("Could not locate dashboard sections.")
            return
        }

        XCTAssertLessThan(
            missionRunnerRange.lowerBound,
            missionConfigRange.lowerBound,
            "The main window should lead with the mission workflow before config diagnostics."
        )
        XCTAssertLessThan(
            missionRunnerRange.lowerBound,
            readinessRange.lowerBound,
            "The main window should lead with the mission workflow before doctor output."
        )
    }

    func testMenuBarSetupCoversNonHostControlBlockers() throws {
        let source = try String(contentsOfFile: "Sources/AURA/Views/MenuBarContentView.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains("!store.cuaStatus.readyForHostControl || !store.canOpenAmbientEntryPoint"),
            "The menu bar setup section should cover both host-control setup and input-readiness blockers."
        )
        XCTAssertTrue(
            source.contains("store.microphonePermissionStatus.setupDetail"),
            "Voice microphone blockers should be explained directly in the menu bar panel."
        )
        XCTAssertTrue(
            source.contains("handleMicrophonePermissionAction"),
            "The menu bar panel should offer the relevant microphone grant/open action when voice is blocked."
        )
    }

    func testMenuBarExtraUsesWindowStyleForDataRichCompanionPanel() throws {
        let source = try String(contentsOfFile: "Sources/AURA/App/AURAApp.swift", encoding: .utf8)
        XCTAssertTrue(
            source.contains(".menuBarExtraStyle(.window)"),
            "AURA's data-rich menu bar companion panel should use SwiftUI MenuBarExtra window style."
        )
    }

    func testNewRequestsOnlyOpenFromGlobalShortcut() throws {
        let dashboardSource = try String(contentsOfFile: "Sources/AURA/Views/ContentView.swift", encoding: .utf8)
        let missionRunnerSource = try String(contentsOfFile: "Sources/AURA/Views/MissionRunnerView.swift", encoding: .utf8)
        let menuSource = try String(contentsOfFile: "Sources/AURA/Views/MenuBarContentView.swift", encoding: .utf8)
        let appSource = try String(contentsOfFile: "Sources/AURA/App/AURAApp.swift", encoding: .utf8)
        let modelSource = try String(contentsOfFile: "Sources/AURA/Models/AURAMission.swift", encoding: .utf8)
        let storeSource = try String(contentsOfFile: "Sources/AURA/Stores/AURAStore.swift", encoding: .utf8)
        let hotKeySource = try String(contentsOfFile: "Sources/AURA/Services/GlobalHotKeyController.swift", encoding: .utf8)
        let visibleUISource = [dashboardSource, missionRunnerSource, menuSource, appSource, modelSource].joined(separator: "\n")

        XCTAssertFalse(
            visibleUISource.contains("New Request"),
            "Dashboard, menu bar, commands, and input-mode labels should not expose a New Request action."
        )
        XCTAssertFalse(
            visibleUISource.contains("aura.newMission"),
            "The dashboard header New Request accessibility hook should not be present."
        )
        XCTAssertFalse(
            visibleUISource.contains("aura.openPanel"),
            "The mission runner New Request accessibility hook should not be present."
        )
        XCTAssertFalse(
            visibleUISource.contains("inputMode.actionTitle"),
            "Input-mode action titles should not drive visible request buttons."
        )
        XCTAssertFalse(
            [dashboardSource, missionRunnerSource, menuSource, appSource].joined(separator: "\n").contains("openMissionInput()"),
            "Dashboard, mission runner, menu bar, and app commands should not directly open the request composer."
        )
        XCTAssertFalse(
            appSource.contains(".keyboardShortcut(\"a\""),
            "The app commands menu should not expose the request shortcut as a visible command."
        )
        XCTAssertTrue(
            storeSource.contains("private lazy var globalHotKey = GlobalHotKeyController { [weak self] in\n        self?.openMissionInput()"),
            "The global shortcut should remain the request entry point."
        )
        XCTAssertTrue(
            hotKeySource.contains("RegisterEventHotKey"),
            "AURA should keep registering the system shortcut."
        )
        XCTAssertTrue(
            hotKeySource.contains("kVK_ANSI_A"),
            "The shortcut should remain bound to A."
        )
        XCTAssertTrue(
            menuSource.contains("Press ⌃⌥⌘A"),
            "The menu bar should explain the shortcut-only request flow instead of showing a button."
        )
    }

}
