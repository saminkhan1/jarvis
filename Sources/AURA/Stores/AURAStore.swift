import AppKit
import Foundation

@MainActor
final class AURAStore: ObservableObject {
    enum HealthState {
        case unknown
        case ready
        case needsSetup
        case warning
        case failed

        var title: String {
            switch self {
            case .unknown:
                return "Unknown"
            case .ready:
                return "Ready"
            case .needsSetup:
                return "Needs setup"
            case .warning:
                return "Warning"
            case .failed:
                return "Failed"
            }
        }
    }

    @Published private(set) var hermesVersion = "Not checked"
    @Published private(set) var healthState: HealthState = .unknown
    @Published private(set) var lastCommand = "None"
    @Published private(set) var lastOutput = "Run a Hermes check to see backend status."
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var hermesSessionsOutput = "Hermes sessions have not been checked yet."
    @Published private(set) var hermesSessionsUpdated: Date?
    @Published private(set) var hermesConfigOutput = "Hermes config has not been checked yet."
    @Published private(set) var hermesConfigUpdated: Date?
    @Published private(set) var isRefreshingHermesConfig = false
    @Published private(set) var readinessOutput = "Hermes diagnostics have not been checked yet."
    @Published private(set) var readinessUpdated: Date?
    @Published private(set) var isRefreshingReadiness = false
    @Published private(set) var isRunning = false
    @Published var missionGoal = ""
    @Published private(set) var voiceInputState: VoiceInputState = .idle
    @Published private(set) var voiceInputLevel: Double = 0
    @Published private(set) var voiceInputDuration: TimeInterval = 0
    @Published private(set) var voiceInputTranscript = ""
    @Published private(set) var voiceInputMessage = "Use the shortcut or click the mic, then start speaking."
    @Published private(set) var microphonePermissionStatus: MicrophonePermissionStatus = .unknown
    @Published private(set) var isRequestingMicrophonePermission = false
    @Published var inputMode: MissionInputMode {
        didSet {
            UserDefaults.standard.set(inputMode.rawValue, forKey: Self.inputModeKey)
            AURATelemetry.info(
                .missionInputModeChanged,
                category: .ui,
                fields: [.string("input_mode", self.inputMode.rawValue)],
                audit: .governance
            )
            refreshMicrophonePermissionStatus()
            syncHostControlAvailability()
            updateCursorIndicator()
        }
    }
    @Published var isAmbientEnabled = true {
        didSet {
            AURATelemetry.info(
                .ambientIndicatorToggled,
                category: .ui,
                fields: [.bool("enabled", self.isAmbientEnabled)]
            )
            updateCursorIndicator()
        }
    }
    @Published private(set) var isShortcutPulseActive = false
    @Published private(set) var missionStatus: MissionStatus = .idle {
        didSet {
            updateCursorIndicator()
        }
    }
    @Published private(set) var missionOutput = "No mission has run yet." {
        didSet {
            updateCursorIndicator()
        }
    }
    @Published private(set) var currentHermesSessionID: String?
    @Published private(set) var contextSnapshot: ContextSnapshot?
    @Published private(set) var cuaStatus: CuaDriverStatus = .unknown {
        didSet {
            syncHostControlAvailability()
        }
    }
    @Published private(set) var isCheckingCua = false
    @Published private(set) var isRunningCuaOnboarding = false
    @Published private(set) var cuaOnboardingMessage = "Complete setup before using AURA."

    private let hermesService = HermesService()
    private let voiceCaptureService = VoiceCaptureService()
    private lazy var cuaDriverService = CuaDriverService()
    private let cursorSurface = CursorSurfaceController()
    private lazy var globalHotKey = GlobalHotKeyController { [weak self] in
        self?.openMissionInput()
    }
    private var missionProcess: Process?
    private var voiceMeterTask: Task<Void, Never>?
    private var voiceTranscriptionTask: Task<Void, Never>?
    private var activeVoiceInputID: UUID?
    private var voiceSpeechStartedAt: Date?
    private var voiceLastSpeechAt: Date?
    private var didRunLaunchOnboarding = false
    private var activeMissionTraceID: String?
    private var activeMissionID: String?
    private var activeMissionStartedAt: Date?
    private var missionOutputChunkCount = 0
    private var lastHostControlReady: Bool?
    private static let inputModeKey = "AURAMissionInputMode"
    private static let hermesToolSurfaceIdentifier = "hermes_config"
    private static let voiceLevelThreshold = 0.075
    private static let voiceSpeechConfirmationSeconds: TimeInterval = 0.3
    private static let voiceSilenceDurationSeconds: TimeInterval = 3.0
    private static let voiceNoSpeechTimeoutSeconds: TimeInterval = 15.0
    private static let voiceMaxRecordingSeconds: TimeInterval = 120.0

    private var activeMissionIDValue: String {
        activeMissionID ?? "none"
    }

    private func missionFields(_ fields: [AURATelemetry.Field] = []) -> [AURATelemetry.Field] {
        [.string("mission_id", activeMissionIDValue)] + fields
    }

    init() {
        let storedInputMode = UserDefaults.standard.string(forKey: Self.inputModeKey)
        inputMode = MissionInputMode(rawValue: storedInputMode ?? "") ?? .text
        microphonePermissionStatus = voiceCaptureService.microphonePermissionStatus()
        updateCursorIndicator()
        syncHostControlAvailability()
        AURATelemetry.info(
            .storeInitialized,
            category: .mission,
            fields: [
                .string("tool_surface", Self.hermesToolSurfaceIdentifier),
                .string("input_mode", self.inputMode.rawValue)
            ],
            audit: .lifecycle
        )
    }

    deinit {
        voiceMeterTask?.cancel()
        voiceTranscriptionTask?.cancel()
        voiceCaptureService.cancelRecording()
    }

    var canStartMission: Bool {
        Self.canStartMission(
            trimmedGoal: missionGoal,
            missionStatusRunning: missionStatus == .running,
            isRunning: isRunning,
            isRunningCuaOnboarding: isRunningCuaOnboarding,
            isRequestingMicrophonePermission: isRequestingMicrophonePermission,
            isMissionInputReady: isMissionInputReady
        )
    }

    var canToggleVoiceInput: Bool {
        inputMode == .voice
            && missionStatus != .running
            && !isRunning
            && !isRunningCuaOnboarding
            && !isRequestingMicrophonePermission
            && microphonePermissionStatus.isGranted
            && voiceInputState != .requestingPermission
            && voiceInputState != .transcribing
    }

    private var canStartVoiceRecording: Bool {
        canToggleVoiceInput && voiceInputState != .recording
    }

    var canCancelVoiceInput: Bool {
        voiceInputState == .recording || voiceInputState == .transcribing
    }

    var canCancelMission: Bool {
        missionStatus == .running
    }

    var canDismissMissionResult: Bool {
        switch missionStatus {
        case .completed, .failed, .cancelled:
            return true
        case .idle, .running:
            return false
        }
    }

    var shouldShowCuaOnboarding: Bool {
        Self.shouldShowCuaOnboarding(
            cuaReadyForHostControl: cuaStatus.readyForHostControl,
            isMissionInputReady: isMissionInputReady,
            isRunningCuaOnboarding: isRunningCuaOnboarding,
            isRequestingMicrophonePermission: isRequestingMicrophonePermission
        )
    }

    var canOpenAmbientEntryPoint: Bool {
        Self.canOpenAmbientEntryPoint(
            isRunningCuaOnboarding: isRunningCuaOnboarding,
            isRequestingMicrophonePermission: isRequestingMicrophonePermission,
            isMissionInputReady: isMissionInputReady
        )
    }

    var isFunctionalSurfaceReady: Bool {
        Self.isFunctionalSurfaceReady(
            cuaReadyForHostControl: cuaStatus.readyForHostControl,
            isMissionInputReady: isMissionInputReady
        )
    }

    var setupStatusTitle: String {
        if isFunctionalSurfaceReady {
            return "Ready"
        }

        if !cuaStatus.readyForHostControl {
            return cuaStatus.title
        }

        if inputMode == .voice && !microphonePermissionStatus.isGranted {
            return "Microphone needed"
        }

        return "Setup needed"
    }

    var microphonePermissionActionTitle: String? {
        guard inputMode == .voice else { return nil }

        switch microphonePermissionStatus {
        case .granted:
            return nil
        case .unknown:
            return "Refresh"
        case .notDetermined:
            return isRequestingMicrophonePermission ? nil : "Grant"
        case .denied, .restricted:
            return "Open"
        }
    }

    private var isMissionInputReady: Bool {
        switch inputMode {
        case .text:
            return true
        case .voice:
            return microphonePermissionStatus.isGranted
        }
    }

    static func canStartMission(
        trimmedGoal: String,
        missionStatusRunning: Bool,
        isRunning: Bool,
        isRunningCuaOnboarding: Bool,
        isRequestingMicrophonePermission: Bool,
        isMissionInputReady: Bool
    ) -> Bool {
        !trimmedGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !missionStatusRunning
            && !isRunning
            && !isRunningCuaOnboarding
            && !isRequestingMicrophonePermission
            && isMissionInputReady
    }

    static func canOpenAmbientEntryPoint(
        isRunningCuaOnboarding: Bool,
        isRequestingMicrophonePermission: Bool,
        isMissionInputReady: Bool
    ) -> Bool {
        !isRunningCuaOnboarding
            && !isRequestingMicrophonePermission
            && isMissionInputReady
    }

    static func isFunctionalSurfaceReady(
        cuaReadyForHostControl: Bool,
        isMissionInputReady: Bool
    ) -> Bool {
        cuaReadyForHostControl && isMissionInputReady
    }

    static func shouldShowCuaOnboarding(
        cuaReadyForHostControl: Bool,
        isMissionInputReady: Bool,
        isRunningCuaOnboarding: Bool,
        isRequestingMicrophonePermission: Bool
    ) -> Bool {
        !isFunctionalSurfaceReady(
            cuaReadyForHostControl: cuaReadyForHostControl,
            isMissionInputReady: isMissionInputReady
        ) || isRunningCuaOnboarding || isRequestingMicrophonePermission
    }

    var hermesToolSurfaceTitle: String {
        "Hermes config"
    }

    var hermesToolSurfaceSummary: String {
        "Tool access, MCP servers, and provider setup are configured by Hermes in .aura/hermes-home/config.yaml."
    }

    var hermesToolSurfaceSystemImage: String {
        "slider.horizontal.3"
    }

    func refreshAll(traceID: String = AURATelemetry.makeTraceID(prefix: "refresh")) async {
        let startedAt = Date()
        AURATelemetry.info(.refreshAllStart, category: .hermes, traceID: traceID)
        await refreshVersion(traceID: traceID)
        await refreshHermesConfigStatus(traceID: traceID)
        await refreshStatus(traceID: traceID)
        await refreshCuaStatus(traceID: traceID)
        await refreshConnectionReadiness(traceID: traceID)
        await refreshHermesSessions(traceID: traceID)
        AURATelemetry.info(
            .refreshAllFinish,
            category: .hermes,
            traceID: traceID,
            fields: [
                .string("health", self.healthState.title),
                .bool("cua_ready", self.cuaStatus.readyForHostControl),
                .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
            ]
        )
    }

    func runLaunchOnboarding() async {
        guard !didRunLaunchOnboarding else { return }
        didRunLaunchOnboarding = true

        let traceID = AURATelemetry.makeTraceID(prefix: "launch")
        let startedAt = Date()
        AURATelemetry.info(.launchOnboardingStart, category: .hermes, traceID: traceID, audit: .lifecycle)
        refreshMicrophonePermissionStatus()
        await refreshVersion(traceID: traceID)
        await refreshHermesConfigStatus(traceID: traceID)
        await refreshStatus(traceID: traceID)
        await refreshPermissionStatus(traceID: traceID)
        await refreshHermesSessions(traceID: traceID)
        AURATelemetry.info(
            .launchOnboardingFinish,
            category: .hermes,
            traceID: traceID,
            fields: [
                .string("health", self.healthState.title),
                .bool("cua_ready", self.cuaStatus.readyForHostControl),
                .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
            ],
            audit: .lifecycle
        )
    }

    func refreshVersion(traceID: String = AURATelemetry.makeTraceID(prefix: "hermes-version")) async {
        await runHermes(arguments: ["version"], traceID: traceID) { [weak self] result in
            self?.hermesVersion = Self.firstMeaningfulLine(in: result.output) ?? "Hermes installed"
            self?.healthState = result.succeeded ? .ready : .failed
        }
    }

    func refreshStatus(traceID: String = AURATelemetry.makeTraceID(prefix: "hermes-status")) async {
        await runHermes(arguments: ["status"], traceID: traceID) { [weak self] result in
            self?.healthState = Self.classifyStatus(result)
        }
    }

    func runDoctor(traceID: String = AURATelemetry.makeTraceID(prefix: "hermes-doctor")) async {
        await runHermes(arguments: ["doctor"], traceID: traceID) { [weak self] result in
            self?.healthState = Self.classifyDoctor(result)
        }
    }

    func refreshHermesSessions(traceID: String = AURATelemetry.makeTraceID(prefix: "hermes-sessions")) async {
        await runHermes(arguments: ["sessions", "list", "--source", "aura", "--limit", "8"], updateLastOutput: false, traceID: traceID) { [weak self] result in
            let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.hermesSessionsOutput = output.isEmpty
                ? "No Hermes sessions found."
                : output
            self?.hermesSessionsUpdated = result.finishedAt
            AURATelemetry.info(
                .hermesSessionsRefreshed,
                category: .hermes,
                traceID: traceID,
                fields: [.int("bytes", AURATelemetry.byteCount(output))]
            )
        }
    }

    func refreshHermesConfigStatus(traceID: String = AURATelemetry.makeTraceID(prefix: "hermes-config")) async {
        guard !isRefreshingHermesConfig else { return }

        isRefreshingHermesConfig = true
        await runHermes(arguments: ["config", "check"], updateLastOutput: false, traceID: traceID) { [weak self] result in
            let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.hermesConfigOutput = output.isEmpty ? "Hermes config check returned no output." : output
            self?.hermesConfigUpdated = result.finishedAt
        }
        isRefreshingHermesConfig = false
    }

    func refreshConnectionReadiness(traceID: String = AURATelemetry.makeTraceID(prefix: "readiness")) async {
        guard !isRefreshingReadiness else { return }

        isRefreshingReadiness = true
        let startedAt = Date()
        let result = try? await hermesService.run(arguments: ["doctor"], traceID: traceID)
        if let result {
            readinessOutput = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            healthState = Self.classifyDoctor(result)
            readinessUpdated = result.finishedAt
        } else {
            readinessOutput = "Hermes doctor failed to run."
            healthState = .failed
            readinessUpdated = Date()
        }
        isRefreshingReadiness = false

        AURATelemetry.info(
            .hermesUICommandFinish,
            category: .hermes,
            traceID: traceID,
            fields: [
                .string("operation", "readiness_refresh"),
                .bool("succeeded", result?.succeeded == true),
                .int("bytes", AURATelemetry.byteCount(readinessOutput)),
                .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
            ],
            audit: .governance
        )
    }

    func openMissionInput() {
        switch inputMode {
        case .text:
            showAmbientEntryPoint()
        case .voice:
            openVoiceEntryPoint()
        }
    }

    private func openVoiceEntryPoint() {
        guard canOpenAmbientEntryPoint else {
            AURATelemetry.warning(
                .ambientPanelBlocked,
                category: .ui,
                fields: [
                    .bool("cua_ready", self.cuaStatus.readyForHostControl),
                    .bool("onboarding", self.isRunningCuaOnboarding),
                    .string("input_mode", self.inputMode.rawValue)
                ],
                audit: .governance
            )
            blockAmbientEntryPoint()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if !isAmbientEnabled {
            isAmbientEnabled = true
        }

        isShortcutPulseActive = true
        updateCursorIndicator()
        showAmbientEntryPoint()
        switch voiceInputState {
        case .recording:
            stopVoiceInputAndTranscribe()
        case .requestingPermission, .transcribing:
            break
        case .idle, .ready, .failed:
            Task { await startVoiceInput() }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            isShortcutPulseActive = false
            updateCursorIndicator()
        }
    }

    func toggleVoiceInput() async {
        guard microphonePermissionStatus.isGranted else {
            refreshMicrophonePermissionStatus()
            blockAmbientEntryPoint()
            voiceInputState = .failed
            voiceInputMessage = microphonePermissionStatus.setupDetail
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard canToggleVoiceInput else { return }

        if voiceInputState == .recording {
            stopVoiceInputAndTranscribe()
        } else {
            await startVoiceInput()
        }
    }

    func clearVoiceInput() {
        cancelVoiceInput()
        voiceInputState = .idle
        voiceInputLevel = 0
        voiceInputDuration = 0
        voiceInputTranscript = ""
        voiceInputMessage = "Use the shortcut or click the mic, then start speaking."
        if inputMode == .voice {
            missionGoal = ""
        }
    }

    func cancelVoiceInput() {
        activeVoiceInputID = nil
        voiceMeterTask?.cancel()
        voiceMeterTask = nil
        voiceTranscriptionTask?.cancel()
        voiceTranscriptionTask = nil
        voiceSpeechStartedAt = nil
        voiceLastSpeechAt = nil
        voiceCaptureService.cancelRecording()
        voiceInputLevel = 0
        voiceInputDuration = 0

        if voiceInputState == .recording || voiceInputState == .transcribing {
            voiceInputState = .idle
            voiceInputMessage = "Voice input cancelled. You can start again anytime."
            AURATelemetry.info(
                .voiceInputCancelled,
                category: .ui,
                fields: [.string("input_mode", self.inputMode.rawValue)],
                audit: .action
            )
        }
    }

    func handleMicrophonePermissionAction() async {
        switch microphonePermissionStatus {
        case .unknown:
            refreshMicrophonePermissionStatus()
        case .notDetermined:
            await requestMicrophonePermission()
        case .denied, .restricted:
            openMicrophonePrivacySettings()
        case .granted:
            break
        }
    }

    func requestMicrophonePermission() async {
        guard !isRequestingMicrophonePermission else { return }

        isRequestingMicrophonePermission = true
        voiceInputState = .requestingPermission
        voiceInputMessage = "Waiting for macOS microphone permission…"
        syncHostControlAvailability()
        defer {
            isRequestingMicrophonePermission = false
            updateCuaOnboardingMessage()
            syncHostControlAvailability()
        }

        let status = await voiceCaptureService.requestMicrophoneAccess()
        microphonePermissionStatus = status
        if status.isGranted {
            voiceInputState = .idle
            voiceInputMessage = "Microphone ready. Use the shortcut or click the mic, then start speaking."
        } else {
            voiceInputState = .failed
            voiceInputMessage = status.setupDetail
            AURATelemetry.warning(
                .voiceInputPermissionDenied,
                category: .ui,
                fields: [.string("input_mode", self.inputMode.rawValue)],
                audit: .governance
            )
        }
    }

    func openMicrophonePrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
            AURATelemetry.info(
                .macPrivacySettingsOpen,
                category: .ui,
                fields: [.string("pane", "Microphone")],
                audit: .governance
            )
        }
    }

    private func startVoiceInput() async {
        guard canStartVoiceRecording else { return }
        guard microphonePermissionStatus.isGranted else {
            refreshMicrophonePermissionStatus()
            blockAmbientEntryPoint()
            voiceInputState = .failed
            voiceInputMessage = microphonePermissionStatus.setupDetail
            AURATelemetry.warning(
                .voiceInputPermissionDenied,
                category: .ui,
                fields: [.string("input_mode", self.inputMode.rawValue)],
                audit: .governance
            )
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let voiceInputID = UUID()
        activeVoiceInputID = voiceInputID
        voiceTranscriptionTask?.cancel()
        voiceTranscriptionTask = nil
        voiceSpeechStartedAt = nil
        voiceLastSpeechAt = nil
        voiceInputState = .recording
        voiceInputMessage = "Opening the microphone…"
        voiceInputTranscript = ""
        voiceInputLevel = 0
        voiceInputDuration = 0
        missionGoal = ""

        guard activeVoiceInputID == voiceInputID, !Task.isCancelled else { return }

        do {
            _ = try voiceCaptureService.startRecording()
            voiceInputState = .recording
            voiceInputMessage = "Listening. Pause after speaking, or click Stop."
            startVoiceMeter()
            AURATelemetry.info(
                .voiceInputRecordStart,
                category: .ui,
                fields: [.string("input_mode", self.inputMode.rawValue)],
                audit: .action
            )
        } catch {
            activeVoiceInputID = nil
            voiceInputState = .failed
            voiceInputMessage = error.localizedDescription
            AURATelemetry.error(
                .voiceInputTranscribeFailed,
                category: .ui,
                fields: [.string("error_type", String(describing: type(of: error)))],
                audit: .action
            )
        }
    }

    private func stopVoiceInputAndTranscribe() {
        guard voiceInputState == .recording,
              let voiceInputID = activeVoiceInputID else { return }
        voiceTranscriptionTask?.cancel()
        voiceTranscriptionTask = Task { @MainActor [weak self] in
            await self?.finishVoiceInputAndTranscribe(voiceInputID: voiceInputID)
        }
    }

    private func finishVoiceInputAndTranscribe(voiceInputID: UUID) async {
        voiceMeterTask?.cancel()
        voiceMeterTask = nil
        voiceInputLevel = 0

        guard activeVoiceInputID == voiceInputID else { return }

        guard let audioURL = voiceCaptureService.stopRecording() else {
            activeVoiceInputID = nil
            voiceInputState = .failed
            voiceInputMessage = "No recording was captured."
            return
        }

        let traceID = AURATelemetry.makeTraceID(prefix: "voice")
        let recordedDuration = voiceInputDuration
        voiceInputState = .transcribing
        voiceInputMessage = "Transcribing with Hermes…"
        AURATelemetry.info(
            .voiceInputRecordStop,
            category: .ui,
            traceID: traceID,
            fields: [
                .int("duration_ms", Int(recordedDuration * 1000)),
                .privateValue("audio_path")
            ],
            audit: .action
        )

        do {
            let result = try await hermesService.run(
                arguments: ["aura-transcribe-audio", audioURL.path],
                traceID: traceID
            )
            try? FileManager.default.removeItem(at: audioURL)
            guard activeVoiceInputID == voiceInputID, !Task.isCancelled else { return }

            guard result.succeeded else {
                throw VoiceTranscriptionError.failed(result.combinedOutput)
            }

            let transcription = try Self.decodeVoiceTranscription(from: result.output)
            let transcript = (transcription.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            guard transcription.success, !transcript.isEmpty else {
                let detail = transcription.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw VoiceTranscriptionError.failed(detail?.isEmpty == false ? detail! : "No speech was detected.")
            }

            voiceInputTranscript = transcript
            missionGoal = transcript
            voiceInputState = .ready
            voiceInputMessage = "Transcript ready. Sending to Hermes…"
            activeVoiceInputID = nil
            lastCommand = "./script/aura-hermes aura-transcribe-audio <recording>"
            lastOutput = "Voice transcript captured for the next mission."
            lastUpdated = Date()
            AURATelemetry.info(
                .voiceInputTranscribeFinish,
                category: .ui,
                traceID: traceID,
                fields: [
                    .int("transcript_chars", transcript.count),
                    .string("provider", transcription.provider ?? "unknown")
                ],
                audit: .action
            )
            await startMission()
        } catch {
            try? FileManager.default.removeItem(at: audioURL)
            guard activeVoiceInputID == voiceInputID, !Task.isCancelled else { return }
            activeVoiceInputID = nil
            voiceInputState = .failed
            voiceInputMessage = error.localizedDescription
            voiceInputTranscript = ""
            missionGoal = ""
            AURATelemetry.error(
                .voiceInputTranscribeFailed,
                category: .ui,
                traceID: traceID,
                fields: [.string("error_type", String(describing: type(of: error)))],
                audit: .action
            )
        }
    }

    private func startVoiceMeter() {
        voiceMeterTask?.cancel()
        voiceMeterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.voiceInputState == .recording else { return }
                let level = self.voiceCaptureService.normalizedInputLevel()
                self.voiceInputLevel = level
                self.voiceInputDuration = self.voiceCaptureService.elapsedSeconds
                self.updateVoiceSilenceDetection(level: level, elapsed: self.voiceInputDuration)
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
        }
    }

    private func updateVoiceSilenceDetection(level: Double, elapsed: TimeInterval) {
        let now = Date()

        if level >= Self.voiceLevelThreshold {
            if voiceSpeechStartedAt == nil {
                voiceSpeechStartedAt = now
            }
            voiceLastSpeechAt = now
        }

        let hasConfirmedSpeech = voiceSpeechStartedAt.map {
            now.timeIntervalSince($0) >= Self.voiceSpeechConfirmationSeconds
        } ?? false

        if hasConfirmedSpeech,
           let voiceLastSpeechAt,
           now.timeIntervalSince(voiceLastSpeechAt) >= Self.voiceSilenceDurationSeconds {
            voiceInputMessage = "Silence detected. Transcribing."
            stopVoiceInputAndTranscribe()
            return
        }

        if !hasConfirmedSpeech, elapsed >= Self.voiceNoSpeechTimeoutSeconds {
            voiceInputMessage = "No speech detected. Transcribing."
            stopVoiceInputAndTranscribe()
            return
        }

        if elapsed >= Self.voiceMaxRecordingSeconds {
            voiceInputMessage = "Recording limit reached. Transcribing."
            stopVoiceInputAndTranscribe()
        }
    }

    func triggerAmbientShortcut() {
        guard canOpenAmbientEntryPoint else {
            AURATelemetry.warning(
                .ambientShortcutBlocked,
                category: .ui,
                fields: [
                    .bool("cua_ready", self.cuaStatus.readyForHostControl),
                    .bool("onboarding", self.isRunningCuaOnboarding),
                    .string("input_mode", self.inputMode.rawValue)
                ],
                audit: .governance
            )
            blockAmbientEntryPoint()
            return
        }

        if !isAmbientEnabled {
            isAmbientEnabled = true
        }

        let traceID = AURATelemetry.makeTraceID(prefix: "ambient")
        AURATelemetry.info(
            .ambientShortcutOpen,
            category: .ui,
            traceID: traceID,
            fields: [
                .string("status", self.missionStatus.title),
                .string("input_mode", self.inputMode.rawValue)
            ]
        )
        captureContextIfStale(traceID: traceID)
        isShortcutPulseActive = true
        updateCursorIndicator()

        if missionStatus != .running {
            missionOutput = inputMode == .voice
                ? "Voice input opened. Listening starts automatically."
                : "Cursor composer opened. Type a mission goal, then press Command-Return."
            lastCommand = "cursor composer shortcut"
            lastOutput = missionOutput
            lastUpdated = Date()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            isShortcutPulseActive = false
            updateCursorIndicator()
        }
    }

    func showAmbientEntryPoint() {
        guard canOpenAmbientEntryPoint else {
            AURATelemetry.warning(
                .ambientPanelBlocked,
                category: .ui,
                fields: [
                    .bool("cua_ready", self.cuaStatus.readyForHostControl),
                    .bool("onboarding", self.isRunningCuaOnboarding),
                    .string("input_mode", self.inputMode.rawValue)
                ],
                audit: .governance
            )
            blockAmbientEntryPoint()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let traceID = AURATelemetry.makeTraceID(prefix: "composer")
        AURATelemetry.info(
            .ambientPanelOpenRequested,
            category: .ui,
            traceID: traceID,
            fields: [
                .string("status", self.missionStatus.title),
                .string("input_mode", self.inputMode.rawValue)
            ]
        )

        // Capture before AURA's composer can become the frontmost app.
        captureContext(traceID: traceID)
        cursorSurface.presentComposer(using: self)
        triggerAmbientShortcut()
    }

    func refreshCuaStatus(traceID: String = AURATelemetry.makeTraceID(prefix: "cua-refresh")) async {
        await refreshPermissionStatus(traceID: traceID)
    }

    func startCuaDriverDaemon(traceID: String = AURATelemetry.makeTraceID(prefix: "cua-daemon")) async {
        guard !isRunningCuaOnboarding else {
            AURATelemetry.warning(
                .cuaDaemonStartIgnored,
                category: .cua,
                traceID: traceID,
                fields: [.string("reason", "onboarding_running")],
                audit: .governance
            )
            return
        }

        let startedAt = Date()
        AURATelemetry.info(.cuaDaemonStartUI, category: .cua, traceID: traceID, audit: .governance)
        isRunningCuaOnboarding = true
        isCheckingCua = true
        defer {
            isCheckingCua = false
            isRunningCuaOnboarding = false
            AURATelemetry.info(
                .cuaDaemonStartUIFinish,
                category: .cua,
                traceID: traceID,
                fields: [
                    .bool("ready", self.cuaStatus.readyForHostControl),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ],
                audit: .governance
            )
        }

        cuaStatus = await cuaDriverService.startHostControlDaemon(traceID: traceID) { [weak self] message in
            await MainActor.run {
                self?.cuaOnboardingMessage = message
                AURATelemetry.info(
                    .cuaOnboardingProgress,
                    category: .cua,
                    traceID: traceID,
                    fields: [.int("message_chars", message.count)]
                )
            }
        }

        updateCuaOnboardingMessage()
    }

    func requestCuaDriverPermissions(
        traceID: String = AURATelemetry.makeTraceID(prefix: "cua-permissions"),
        focusing pane: CuaPermissionPane? = nil
    ) async {
        guard !isRunningCuaOnboarding else {
            AURATelemetry.warning(
                .cuaPermissionsRequestIgnored,
                category: .cua,
                traceID: traceID,
                fields: [.string("reason", "onboarding_running")],
                audit: .governance
            )
            return
        }

        let startedAt = Date()
        AURATelemetry.info(
            .cuaPermissionsRequestUI,
            category: .cua,
            traceID: traceID,
            fields: [.string("focus_pane", pane?.rawValue ?? "auto")],
            audit: .governance
        )
        isRunningCuaOnboarding = true
        isCheckingCua = true
        defer {
            isCheckingCua = false
            isRunningCuaOnboarding = false
            AURATelemetry.info(
                .cuaPermissionsRequestUIFinish,
                category: .cua,
                traceID: traceID,
                fields: [
                    .bool("ready", self.cuaStatus.readyForHostControl),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ],
                audit: .governance
            )
        }

        cuaStatus = await cuaDriverService.requestHostControlPermissions(traceID: traceID, focusing: pane) { [weak self] message in
            await MainActor.run {
                self?.cuaOnboardingMessage = message
                AURATelemetry.info(
                    .cuaOnboardingProgress,
                    category: .cua,
                    traceID: traceID,
                    fields: [.int("message_chars", message.count)]
                )
            }
        }

        updateCuaOnboardingMessage()
    }

    func refreshPermissionStatus(
        traceID: String = AURATelemetry.makeTraceID(prefix: "cua-refresh"),
        telemetryEnabled: Bool = true
    ) async {
        refreshMicrophonePermissionStatus()

        guard !isRunningCuaOnboarding, !isCheckingCua else {
            if telemetryEnabled {
                AURATelemetry.debug(
                    .cuaRefreshSkipped,
                    category: .cua,
                    traceID: traceID,
                    fields: [
                        .bool("onboarding", self.isRunningCuaOnboarding),
                        .bool("checking", self.isCheckingCua)
                    ]
                )
            }
            return
        }

        let startedAt = Date()
        if telemetryEnabled {
            AURATelemetry.info(.cuaRefreshStart, category: .cua, traceID: traceID)
        }
        isCheckingCua = true
        defer {
            isCheckingCua = false
            if telemetryEnabled {
                AURATelemetry.info(
                    .cuaRefreshFinish,
                    category: .cua,
                    traceID: traceID,
                    fields: [
                        .bool("ready", self.cuaStatus.readyForHostControl),
                        .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                    ]
                )
            }
        }

        cuaStatus = await cuaDriverService.prepareHostControl(traceID: traceID, telemetryEnabled: telemetryEnabled) { [weak self] message in
            await MainActor.run {
                self?.cuaOnboardingMessage = message
                if telemetryEnabled {
                    AURATelemetry.debug(
                        .cuaOnboardingProgress,
                        category: .cua,
                        traceID: traceID,
                        fields: [.int("message_chars", message.count)]
                    )
                }
            }
        }
        refreshMicrophonePermissionStatus()
        updateCuaOnboardingMessage()
    }

    private func refreshMicrophonePermissionStatus() {
        microphonePermissionStatus = voiceCaptureService.microphonePermissionStatus()
        updateCuaOnboardingMessage()
    }

    private func updateCuaOnboardingMessage() {
        if inputMode == .voice && !isMissionInputReady {
            cuaOnboardingMessage = "Voice input needs microphone access before it can start."
            return
        }

        if cuaStatus.readyForHostControl {
            cuaOnboardingMessage = "Setup is ready. Host control is available."
            return
        }

        let issues = cuaStatus.issues
        cuaOnboardingMessage = issues.isEmpty
            ? "Hermes chat is available. Complete CUA setup before using host control."
            : "Hermes chat is available. Complete CUA setup before using host control: \(issues.joined(separator: " "))"
    }

    func registerCuaDriverWithHermes(traceID: String = AURATelemetry.makeTraceID(prefix: "cua-mcp")) async {
        let startedAt = Date()
        AURATelemetry.info(.cuaMCPRegisterStart, category: .cua, traceID: traceID, audit: .governance)

        if cuaStatus.lastCheckedAt == nil {
            await refreshCuaStatus(traceID: traceID)
        }

        guard cuaDriverService.recommendedMCPCommandPath(for: cuaStatus) != nil else {
            lastCommand = "register cua-driver MCP"
            lastOutput = "Cua Driver is not installed. Install it first, then register the MCP server."
            lastUpdated = Date()
            AURATelemetry.warning(
                .cuaMCPRegisterBlocked,
                category: .cua,
                traceID: traceID,
                fields: [
                    .string("reason", "cua_not_installed"),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ],
                audit: .governance
            )
            return
        }

        guard let proxyPath = cuaDriverService.recommendedMCPProxyCommandPath() else {
            lastCommand = "register cua-driver MCP"
            lastOutput = "AURA CUA MCP proxy is missing or not executable."
            lastUpdated = Date()
            AURATelemetry.error(
                .cuaMCPRegisterBlocked,
                category: .cua,
                traceID: traceID,
                fields: [
                    .string("reason", "proxy_missing"),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ],
                audit: .governance
            )
            return
        }

        await runHermes(arguments: [
            "mcp",
            "add",
            "cua-driver",
            "--command",
            proxyPath
        ], traceID: traceID) { [weak self] result in
            if result.succeeded {
                self?.lastOutput = "Registered Cua Driver MCP through AURA's daemon proxy. Tool exposure stays in Hermes config.\n\n\(result.combinedOutput)"
            }
        }

        await refreshCuaStatus(traceID: traceID)
        AURATelemetry.info(
            .cuaMCPRegisterFinish,
            category: .cua,
            traceID: traceID,
            fields: [
                .bool("registered", self.cuaStatus.isMCPRegistered),
                .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
            ],
            audit: .governance
        )
    }

    func captureContext(traceID: String = AURATelemetry.makeTraceID(prefix: "context")) {
        let snapshot = ContextSnapshot.capture()
        contextSnapshot = snapshot
        logContextCaptured(snapshot, traceID: traceID)
    }

    private func captureContextIfStale(
        traceID: String,
        maxAge: TimeInterval = 2
    ) {
        if let contextSnapshot,
           Date().timeIntervalSince(contextSnapshot.capturedAt) <= maxAge {
            AURATelemetry.info(
                .contextReused,
                category: .ui,
                traceID: traceID,
                fields: [.int("age_ms", AURATelemetry.durationMilliseconds(from: contextSnapshot.capturedAt))]
            )
            return
        }

        captureContext(traceID: traceID)
    }

    private func missionContextSnapshot(traceID: String, maxAge: TimeInterval = 120) -> ContextSnapshot {
        if let contextSnapshot,
           Date().timeIntervalSince(contextSnapshot.capturedAt) <= maxAge {
            AURATelemetry.info(
                .contextReused,
                category: .ui,
                traceID: traceID,
                fields: [.int("age_ms", AURATelemetry.durationMilliseconds(from: contextSnapshot.capturedAt))]
            )
            return contextSnapshot
        }

        let snapshot = ContextSnapshot.capture()
        contextSnapshot = snapshot
        logContextCaptured(snapshot, traceID: traceID)
        return snapshot
    }

    private func logContextCaptured(_ snapshot: ContextSnapshot, traceID: String) {
        AURATelemetry.info(
            .contextCaptured,
            category: .ui,
            traceID: traceID,
            fields: [
                .privateValue("active_app"),
                .privateValue("bundle_id"),
                .int32("active_process_id", snapshot.processIdentifier ?? -1, audit: false),
                .int("cursor_x", Int(snapshot.cursorX), audit: false),
                .int("cursor_y", Int(snapshot.cursorY), audit: false)
            ]
        )
    }

    func startMission() async {
        guard missionStatus != .running else {
            let traceID = activeMissionTraceID ?? AURATelemetry.makeTraceID(prefix: "mission")
            AURATelemetry.warning(
                .missionStartIgnored,
                category: .mission,
                traceID: traceID,
                fields: missionFields([.string("reason", "already_running")]),
                audit: .mission
            )
            return
        }

        let traceID = AURATelemetry.makeTraceID(prefix: "mission")
        let missionID = AURATelemetry.makeSpanID(prefix: "mission")
        let requestedAt = Date()
        activeMissionTraceID = traceID
        activeMissionID = missionID
        activeMissionStartedAt = requestedAt
        missionOutputChunkCount = 0

        let trimmedGoal = missionGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        AURATelemetry.info(
            .missionStartRequested,
            category: .mission,
            traceID: traceID,
            fields: missionFields([
                .string("operation", "invoke_agent"),
                .string("tool_surface", Self.hermesToolSurfaceIdentifier),
                .int("goal_chars", trimmedGoal.count)
            ]),
            audit: .mission
        )

        guard isMissionInputReady else {
            AURATelemetry.warning(
                .missionStartBlocked,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .string("reason", "input_not_ready"),
                    .string("input_mode", self.inputMode.rawValue),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: requestedAt))
                ]),
                audit: .mission
            )
            blockAmbientEntryPoint()
            clearActiveMissionTrace()
            return
        }

        guard !trimmedGoal.isEmpty else {
            AURATelemetry.warning(
                .missionStartBlocked,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .string("reason", "empty_goal"),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: requestedAt))
                ]),
                audit: .mission
            )
            missionStatus = .failed
            missionOutput = "Enter a mission goal before starting Hermes."
            lastOutput = missionOutput
            lastUpdated = Date()
            clearActiveMissionTrace()
            return
        }

        currentHermesSessionID = nil
        contextSnapshot = missionContextSnapshot(traceID: traceID)

        missionStatus = .running
        missionOutput = "Starting Hermes...\n"
        lastCommand = "./script/aura-hermes chat -Q --yolo --source aura -q <user prompt>"
        lastOutput = missionOutput
        lastUpdated = Date()

        do {
            AURATelemetry.info(
                .missionLaunchHermes,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .string("operation", "invoke_agent"),
                    .string("tool_surface", Self.hermesToolSurfaceIdentifier)
                ]),
                audit: .agent
            )
            try launchHermes(arguments: Self.hermesChatArguments(
                query: trimmedGoal
            ), environment: Self.hermesEnvironment(
                missionID: activeMissionID
            ), traceID: traceID)
        } catch {
            AURATelemetry.error(
                .missionLaunchFailed,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .string("error_type", String(describing: type(of: error))),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: requestedAt))
                ]),
                audit: .mission
            )
            missionStatus = .failed
            missionOutput = error.localizedDescription
            lastOutput = missionOutput
            lastUpdated = Date()
            clearActiveMissionTrace()
        }
    }

    func cancelMission() {
        guard let missionProcess, missionStatus == .running else { return }
        let traceID = activeMissionTraceID ?? AURATelemetry.makeTraceID(prefix: "mission")
        missionProcess.terminate()
        self.missionProcess = nil
        missionStatus = .cancelled
        AURATelemetry.info(
            .missionCancelledByUser,
            category: .mission,
            traceID: traceID,
            fields: missionFields([
                .int32("child_process_id", missionProcess.processIdentifier),
                .int("duration_ms", self.activeMissionStartedAt.map { AURATelemetry.durationMilliseconds(from: $0) } ?? 0)
            ]),
            audit: .mission
        )
        appendMissionOutput("\nMission cancelled by user.")
        clearActiveMissionTrace()
    }

    func dismissMissionResult() {
        guard canDismissMissionResult else { return }
        currentHermesSessionID = nil
        missionStatus = .idle
        missionOutput = ""
        lastUpdated = Date()
        clearActiveMissionTrace()
    }

    func copySetupCommand() {
        let command = "cd \(AURAPaths.projectRoot.path) && ./script/aura-hermes setup"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        lastOutput = "Copied setup command:\n\(command)"
        lastCommand = "copy setup command"
        lastUpdated = Date()
        AURATelemetry.info(.setupCommandCopied, category: .ui)
    }

    func copyCuaInstallCommand() {
        let command = "cd \(AURAPaths.projectRoot.path) && ./script/setup.sh"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        lastCommand = "copy cua install command"
        lastOutput = "Copied AURA setup command:\n\(command)"
        lastUpdated = Date()
        AURATelemetry.info(.cuaInstallCommandCopied, category: .ui)
    }

    func copyCuaDaemonCommand() {
        let command = "open -n -g /Applications/CuaDriver.app --args serve"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        lastCommand = "copy cua daemon command"
        lastOutput = "Copied Cua Driver daemon command:\n\(command)"
        lastUpdated = Date()
        AURATelemetry.info(.cuaDaemonCommandCopied, category: .ui)
    }

    func openProjectFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([AURAPaths.projectRoot])
        AURATelemetry.info(
            .projectFolderOpened,
            category: .ui,
            fields: [.privateValue("path")]
        )
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    func openHermesConfigFile() {
        let configURL = AURAPaths.hermesHome.appendingPathComponent("config.yaml")
        NSWorkspace.shared.open(configURL)
        lastCommand = "open Hermes config"
        lastOutput = "Opened project-local Hermes config at \(configURL.path)"
        lastUpdated = Date()
    }

    func revealHermesConfigFile() {
        let configURL = AURAPaths.hermesHome.appendingPathComponent("config.yaml")
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
        lastCommand = "reveal Hermes config"
        lastOutput = "Revealed project-local Hermes config at \(configURL.path)"
        lastUpdated = Date()
    }

    private func runHermes(
        arguments: [String],
        updateLastOutput: Bool = true,
        traceID: String = AURATelemetry.makeTraceID(prefix: "hermes-ui"),
        onSuccess: @escaping (HermesCommandResult) -> Void
    ) async {
        let startedAt = Date()
        let operation = AURATelemetry.hermesOperation(arguments: arguments)
        isRunning = true
        lastCommand = "./script/aura-hermes \(arguments.joined(separator: " "))"
        AURATelemetry.info(
            .hermesUICommandStart,
            category: .hermes,
            traceID: traceID,
            fields: [.string("operation", operation)]
        )

        do {
            let result = try await hermesService.run(arguments: arguments, traceID: traceID)
            if updateLastOutput {
                lastOutput = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            lastUpdated = result.finishedAt
            AURATelemetry.info(
                .hermesUICommandFinish,
                category: .hermes,
                traceID: traceID,
                fields: [
                    .string("operation", operation),
                    .int32("exit_code", result.exitCode),
                    .int("duration_ms", result.durationMilliseconds)
                ]
            )
            onSuccess(result)
        } catch {
            healthState = .failed
            lastOutput = error.localizedDescription
            lastUpdated = Date()
            AURATelemetry.error(
                .hermesUICommandFailed,
                category: .hermes,
                traceID: traceID,
                fields: [
                    .string("operation", operation),
                    .string("error_type", String(describing: type(of: error))),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ]
            )
        }

        isRunning = false
    }

    private func appendMissionOutput(_ chunk: String) {
        guard !chunk.isEmpty else { return }

        missionOutputChunkCount += 1
        if let traceID = activeMissionTraceID {
            AURATelemetry.debug(
                .missionOutputChunk,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .int("chunk_index", self.missionOutputChunkCount),
                    .int("bytes", AURATelemetry.byteCount(chunk))
                ])
            )
        }
        missionOutput += chunk
        lastOutput = missionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        lastUpdated = Date()
    }

    nonisolated static func hermesChatArguments(query: String) -> [String] {
        var arguments = ["chat", "-Q", "--yolo", "--source", "aura"]
        arguments.append(contentsOf: ["-q", query])
        return arguments
    }

    private static func hermesEnvironment(missionID: String?) -> [String: String] {
        [
            "AURA_MISSION_ID": missionID ?? "none"
        ]
    }

    private func launchHermes(arguments: [String], environment: [String: String], traceID: String) throws {
        let process = try hermesService.start(
            arguments: arguments,
            environment: environment,
            traceID: traceID,
            onOutput: { [weak self] chunk in
                Task { @MainActor in
                    self?.appendMissionOutput(chunk)
                }
            },
            onCompletion: { [weak self] result in
                Task { @MainActor in
                    self?.finishMission(result)
                }
            }
        )
        missionProcess = process
    }

    private func finishMission(_ result: Result<HermesCommandResult, Error>) {
        missionProcess = nil

        switch result {
        case .success(let commandResult):
            let traceID = commandResult.traceID
            if missionStatus == .cancelled {
                AURATelemetry.info(
                    .missionFinishAfterCancel,
                    category: .mission,
                    traceID: traceID,
                    fields: missionFields([
                        .int32("exit_code", commandResult.exitCode),
                        .int("hermes_duration_ms", commandResult.durationMilliseconds)
                    ]),
                    audit: .mission
                )
                clearActiveMissionTrace()
                return
            }

            let combinedOutput = commandResult.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdoutOutput = commandResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let output = commandResult.succeeded && !stdoutOutput.isEmpty ? stdoutOutput : combinedOutput
            let parsedSessionID = AURASessionParsing.sessionID(in: combinedOutput)
            currentHermesSessionID = parsedSessionID ?? currentHermesSessionID
            if let parsedSessionID {
                AURATelemetry.info(
                    .hermesSessionCaptured,
                    category: .hermes,
                    traceID: traceID,
                    fields: missionFields([.string("hermes_session_id", parsedSessionID)]),
                    audit: .agent
                )
            }
            missionOutput = output.isEmpty ? "Hermes returned no mission output." : output
            lastOutput = missionOutput
            lastUpdated = commandResult.finishedAt

            missionStatus = commandResult.succeeded ? .completed : .failed
            let missionDuration = activeMissionStartedAt.map { AURATelemetry.durationMilliseconds(from: $0, to: commandResult.finishedAt) } ?? commandResult.durationMilliseconds
            AURATelemetry.info(
                .missionFinish,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .string("status", self.missionStatus.title),
                    .int32("exit_code", commandResult.exitCode),
                    .int("mission_duration_ms", missionDuration),
                    .int("hermes_duration_ms", commandResult.durationMilliseconds),
                    .int("stdout_bytes", commandResult.outputByteCount),
                    .int("stderr_bytes", commandResult.errorByteCount),
                    .int("output_chunks", self.missionOutputChunkCount)
                ]),
                audit: .mission
            )
            clearActiveMissionTrace()
        case .failure(let error):
            let traceID = activeMissionTraceID ?? AURATelemetry.makeTraceID(prefix: "mission")
            missionStatus = .failed
            missionOutput = error.localizedDescription
            lastOutput = missionOutput
            lastUpdated = Date()
            AURATelemetry.error(
                .missionFinishFailed,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .string("error_type", String(describing: type(of: error))),
                    .int("duration_ms", self.activeMissionStartedAt.map { AURATelemetry.durationMilliseconds(from: $0) } ?? 0)
                ]),
                audit: .mission
            )
            clearActiveMissionTrace()
        }
    }

    private func blockAmbientEntryPoint() {
        AURATelemetry.warning(
            .functionalSurfaceBlocked,
            category: .ui,
            fields: [
                .bool("cua_ready", self.cuaStatus.readyForHostControl),
                .bool("input_ready", self.isMissionInputReady),
                .int("issue_count", self.readinessIssues.count)
            ],
            audit: .governance
        )
        missionOutput = inputMode == .voice
            ? "Voice input is unavailable until microphone setup is complete."
            : "Ambient entry is temporarily unavailable."
        lastCommand = "ambient entry check"
        lastOutput = "\(missionOutput)\n\(readinessIssuesText())"
        lastUpdated = Date()
        updateCuaOnboardingMessage()
    }

    private func readinessIssuesText() -> String {
        readinessIssues.joined(separator: " ")
    }

    private var readinessIssues: [String] {
        var result = cuaStatus.issues
        if inputMode == .voice,
           let microphoneIssue = microphonePermissionStatus.setupIssue {
            result.append(microphoneIssue)
        }
        return result
    }

    private func syncHostControlAvailability() {
        let ready = cuaStatus.readyForHostControl
        if lastHostControlReady != ready {
            AURATelemetry.info(
                .hostControlStateChanged,
                category: .cua,
                fields: [
                    .bool("ready", ready),
                    .string("title", self.setupStatusTitle),
                    .int("issue_count", self.readinessIssues.count)
                ],
                audit: .governance
            )
            lastHostControlReady = ready
        }

        if canOpenAmbientEntryPoint {
            globalHotKey.register()
        } else {
            globalHotKey.unregister()
            if isRequestingMicrophonePermission {
                cursorSurface.hide()
                isShortcutPulseActive = false
            } else {
                blockAmbientEntryPoint()
            }
        }
        updateCursorIndicator()
    }

    private func updateCursorIndicator() {
        cursorSurface.setVisible(isAmbientEnabled && canOpenAmbientEntryPoint, store: self)
    }

    private func clearActiveMissionTrace() {
        activeMissionTraceID = nil
        activeMissionID = nil
        activeMissionStartedAt = nil
        missionOutputChunkCount = 0
    }

    private static func sessionID(in output: String) -> String? {
        AURASessionParsing.sessionID(in: output)
    }

    private static func decodeVoiceTranscription(from output: String) throws -> VoiceTranscriptionResponse {
        let jsonLine = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .reversed()
            .first { $0.hasPrefix("{") && $0.hasSuffix("}") }

        guard let jsonLine, let data = jsonLine.data(using: .utf8) else {
            throw VoiceTranscriptionError.failed("Hermes did not return a transcription result.")
        }

        return try JSONDecoder().decode(VoiceTranscriptionResponse.self, from: data)
    }

    private static func firstMeaningfulLine(in text: String) -> String? {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func classifyStatus(_ result: HermesCommandResult) -> HealthState {
        guard result.succeeded else { return .failed }

        if hasUsableProvider(in: result.output) {
            return .ready
        }

        return .needsSetup
    }

    private static func classifyDoctor(_ result: HermesCommandResult) -> HealthState {
        guard result.succeeded else { return .failed }

        if hasUsableProvider(in: result.output) {
            return result.output.contains("Found 1 issue") ? .warning : .ready
        }

        if result.output.contains("Run 'hermes setup'") || result.output.contains("not configured") {
            return .needsSetup
        }

        if result.output.contains("⚠") || result.output.localizedCaseInsensitiveContains("warning") {
            return .warning
        }

        return .ready
    }

    private static func hasUsableProvider(in output: String) -> Bool {
        output.contains("Provider:     OpenAI Codex")
            || output.contains("OpenAI Codex  ✓ logged in")
            || output.contains("✓ OpenAI Codex auth (logged in)")
            || output.contains("openai-codex: logged in")
    }
}

private struct VoiceTranscriptionResponse: Decodable {
    let success: Bool
    let transcript: String?
    let error: String?
    let provider: String?
}

private enum VoiceTranscriptionError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Voice transcription failed."
                : message
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
