import XCTest
@testable import AURA

@MainActor
final class ReadinessGatingTests: XCTestCase {
    func testMissionStartDoesNotRequireHostControlReadinessForNormalChat() {
        XCTAssertTrue(
            AURAStore.canStartMission(
                trimmedGoal: "Summarize logs",
                missionStatusRunning: false,
                isRunning: false,
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false,
                isMissionInputReady: true
            )
        )
    }

    func testMissionStartRequiresReadyInputAndIdleExecutionState() {
        XCTAssertTrue(
            AURAStore.canStartMission(
                trimmedGoal: "Summarize logs",
                missionStatusRunning: false,
                isRunning: false,
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false,
                isMissionInputReady: true
            )
        )

        XCTAssertFalse(
            AURAStore.canStartMission(
                trimmedGoal: "Summarize logs",
                missionStatusRunning: true,
                isRunning: false,
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false,
                isMissionInputReady: true
            )
        )

        XCTAssertFalse(
            AURAStore.canStartMission(
                trimmedGoal: "   ",
                missionStatusRunning: false,
                isRunning: false,
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false,
                isMissionInputReady: true
            )
        )

        XCTAssertFalse(
            AURAStore.canStartMission(
                trimmedGoal: "Summarize logs",
                missionStatusRunning: false,
                isRunning: false,
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false,
                isMissionInputReady: false
            )
        )
    }

    func testAmbientEntryPointRequiresReadyInputButNotHostControl() {
        XCTAssertTrue(
            AURAStore.canOpenAmbientEntryPoint(
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false,
                isMissionInputReady: true
            )
        )

        XCTAssertFalse(
            AURAStore.canOpenAmbientEntryPoint(
                isRunningCuaOnboarding: true,
                isRequestingMicrophonePermission: false,
                isMissionInputReady: true
            )
        )

        XCTAssertFalse(
            AURAStore.canOpenAmbientEntryPoint(
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: true,
                isMissionInputReady: true
            )
        )

        XCTAssertFalse(
            AURAStore.canOpenAmbientEntryPoint(
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false,
                isMissionInputReady: false
            )
        )
    }

    func testHermesComputerUseToolsListParsingRequiresEnabledComputerUseRow() {
        let disabledOutput = """
        Built-in toolsets (cli):
          ✓ enabled  web  🔍 Web Search & Scraping
          ✗ disabled  computer_use  🖱️  Computer Use (macOS)
        """
        XCTAssertFalse(CuaDriverService.hermesComputerUseEnabled(in: disabledOutput))
        XCTAssertFalse(CuaDriverService.hermesComputerUseEnabled(in: "computer_use not enabled"))

        let enabledOutput = """
        Built-in toolsets (cli):
          ✓ enabled  web  🔍 Web Search & Scraping
          ✓ enabled  computer_use  🖱️  Computer Use (macOS)
        """
        XCTAssertTrue(CuaDriverService.hermesComputerUseEnabled(in: enabledOutput))
    }

    func testHostControlRequiresHermesComputerUseSmokeNotJustStaticChecks() {
        let status = CuaDriverStatus(
            executablePath: "/Users/example/AURA.app/Contents/MacOS/cua-driver",
            version: "cua-driver 0.0.5",
            daemonStatus: "AURA host-control helper is running",
            accessibilityGranted: true,
            screenRecordingGranted: true,
            isHermesComputerUseEnabled: true,
            isHermesComputerUseSmokePassed: false,
            lastCheckedAt: Date()
        )

        XCTAssertFalse(status.readyForHostControl)
        XCTAssertTrue(status.issues.contains("Verify Hermes computer_use can list apps and capture the screen."))
    }

    func testHermesComputerUseSmokePromptRequiresListAppsAndCapture() {
        let prompt = CuaDriverService.hermesComputerUseSmokePrompt

        XCTAssertTrue(prompt.contains("action=list_apps"), prompt)
        XCTAssertTrue(prompt.contains("action=capture"), prompt)
        XCTAssertTrue(prompt.contains("read-only"), prompt)
        XCTAssertTrue(prompt.contains("Do not click or type"), prompt)
    }

    func testOnboardingVisibilityTracksCapabilitySpecificReadiness() {
        XCTAssertTrue(
            AURAStore.shouldShowCuaOnboarding(
                cuaReadyForHostControl: false,
                isMissionInputReady: true,
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false
            )
        )

        XCTAssertTrue(
            AURAStore.shouldShowCuaOnboarding(
                cuaReadyForHostControl: true,
                isMissionInputReady: false,
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false
            )
        )

        XCTAssertFalse(
            AURAStore.shouldShowCuaOnboarding(
                cuaReadyForHostControl: true,
                isMissionInputReady: true,
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false
            )
        )
    }
}
