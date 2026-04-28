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
