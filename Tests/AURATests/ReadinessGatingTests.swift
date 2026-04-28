import XCTest
@testable import AURA

@MainActor
final class ReadinessGatingTests: XCTestCase {
    func testMissionStartRequiresHostControlReadinessUnderCurrentGlobalGate() {
        XCTAssertFalse(
            AURAStore.canStartMission(
                trimmedGoal: "Summarize logs",
                missionStatusRunning: false,
                isRunning: false,
                isRunningCuaOnboarding: false,
                isRequestingMicrophonePermission: false,
                cuaReadyForHostControl: false,
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
                cuaReadyForHostControl: true,
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
                cuaReadyForHostControl: true,
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
                cuaReadyForHostControl: true,
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
                cuaReadyForHostControl: true,
                isMissionInputReady: false
            )
        )
    }

    func testOnboardingVisibilityTracksCurrentGlobalFunctionalReadinessModel() {
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
