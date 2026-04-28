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
