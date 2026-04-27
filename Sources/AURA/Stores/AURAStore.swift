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
    @Published private(set) var hermesSessions: [HermesSessionSummary] = []
    @Published private(set) var hermesSessionsUpdated: Date?
    @Published private(set) var isRunning = false
    @Published var missionGoal = ""
    @Published var inputMode: MissionInputMode {
        didSet {
            UserDefaults.standard.set(inputMode.rawValue, forKey: Self.inputModeKey)
            AURATelemetry.info(
                .missionInputModeChanged,
                category: .ui,
                fields: [.string("input_mode", self.inputMode.rawValue)],
                audit: .governance
            )
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
    @Published private(set) var workerRuns: [WorkerRun] = []
    @Published private(set) var artifacts: [AURAArtifact] = []
    @Published private(set) var pendingApproval: ApprovalRequest? {
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
    @Published private(set) var cuaOnboardingMessage = "Complete CUA setup before using AURA."

    private let hermesService = HermesService()
    private lazy var cuaDriverService = CuaDriverService(hermesService: hermesService)
    private let cursorSurface = CursorSurfaceController()
    private lazy var globalHotKey = GlobalHotKeyController { [weak self] in
        self?.openMissionInput()
    }
    private var missionProcess: Process?
    private var missionTimeoutTask: Task<Void, Never>?
    private var readinessMonitorTask: Task<Void, Never>?
    private var didRunLaunchOnboarding = false
    private var activeMissionTraceID: String?
    private var activeMissionID: String?
    private var activeMissionStartedAt: Date?
    private var timedOutMissionTraceID: String?
    private var missionOutputChunkCount = 0
    private var missionRetryCount = 0
    private var lastHostControlReady: Bool?
    private static let inputModeKey = "AURAMissionInputMode"
    private static let hermesToolSurfaceIdentifier = "hermes_config"
    private static let missionTimeoutSeconds: UInt64 = 300

    private var activeMissionIDValue: String {
        activeMissionID ?? "none"
    }

    private func missionFields(_ fields: [AURATelemetry.Field] = []) -> [AURATelemetry.Field] {
        [.string("mission_id", activeMissionIDValue)] + fields
    }

    init() {
        let storedInputMode = UserDefaults.standard.string(forKey: Self.inputModeKey)
        inputMode = MissionInputMode(rawValue: storedInputMode ?? "") ?? .text
        updateCursorIndicator()
        syncHostControlAvailability()
        startReadinessMonitor()
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
        readinessMonitorTask?.cancel()
    }

    var canStartMission: Bool {
        !missionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && missionStatus != .running
            && !isRunning
            && !isRunningCuaOnboarding
            && cuaStatus.readyForHostControl
    }

    var canCancelMission: Bool {
        missionStatus == .running
    }

    var canApproveMission: Bool {
        pendingApproval != nil
            && missionStatus == .needsApproval
            && currentHermesSessionID?.isEmpty == false
            && !isRunning
            && !isRunningCuaOnboarding
            && cuaStatus.readyForHostControl
    }

    var shouldShowCuaOnboarding: Bool {
        !cuaStatus.readyForHostControl || isRunningCuaOnboarding
    }

    var canOpenAmbientEntryPoint: Bool {
        cuaStatus.readyForHostControl && !isRunningCuaOnboarding
    }

    var hermesToolSurfaceTitle: String {
        "Hermes config"
    }

    var hermesToolSurfaceSummary: String {
        "Tool exposure, MCP servers, approvals, and provider setup are owned by project-local Hermes in .aura/hermes-home/config.yaml."
    }

    var hermesToolSurfaceSystemImage: String {
        "slider.horizontal.3"
    }

    func refreshAll(traceID: String = AURATelemetry.makeTraceID(prefix: "refresh")) async {
        let startedAt = Date()
        AURATelemetry.info(.refreshAllStart, category: .hermes, traceID: traceID)
        await refreshVersion(traceID: traceID)
        await refreshStatus(traceID: traceID)
        await refreshCuaStatus(traceID: traceID)
        if cuaStatus.readyForHostControl {
            await refreshHermesSessions(traceID: traceID)
        }
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
        await refreshVersion(traceID: traceID)
        await refreshStatus(traceID: traceID)
        await refreshPermissionStatus(traceID: traceID)
        if cuaStatus.readyForHostControl {
            await refreshHermesSessions(traceID: traceID)
        }
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
        await runHermes(arguments: ["sessions", "export", "-"], updateLastOutput: false, traceID: traceID) { [weak self] result in
            let sessions = HermesSessionSummary.parseJSONL(result.output, limit: 8)
            self?.hermesSessions = sessions
            self?.hermesSessionsOutput = sessions.isEmpty
                ? "No Hermes sessions found."
                : "Showing \(sessions.count) Hermes session summaries from structured export."
            self?.hermesSessionsUpdated = result.finishedAt
            AURATelemetry.info(
                .hermesSessionsRefreshed,
                category: .hermes,
                traceID: traceID,
                fields: [.int("count", sessions.count)]
            )
        }
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
        openHermesVoiceMode(autoEnable: true)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            isShortcutPulseActive = false
            updateCursorIndicator()
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
                .bool("has_pending_approval", self.pendingApproval != nil),
                .string("input_mode", self.inputMode.rawValue)
            ]
        )
        captureContext(traceID: traceID)
        isShortcutPulseActive = true
        updateCursorIndicator()

        if missionStatus != .running && pendingApproval == nil {
            missionOutput = "Cursor composer opened. Type a mission goal, then press Command-Return."
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
                .bool("has_pending_approval", self.pendingApproval != nil),
                .string("input_mode", self.inputMode.rawValue)
            ]
        )

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
        updateCuaOnboardingMessage()
    }

    private func updateCuaOnboardingMessage() {
        if cuaStatus.readyForHostControl {
            cuaOnboardingMessage = "CUA host control is ready. AURA is unlocked."
            return
        }

        cuaOnboardingMessage = cuaStatus.issues.isEmpty
            ? "Complete CUA setup before using AURA."
            : "AURA is locked until: \(cuaStatus.issues.joined(separator: " "))"
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
        missionRetryCount = 0

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

        await refreshCuaStatus(traceID: traceID)
        guard cuaStatus.readyForHostControl else {
            AURATelemetry.warning(
                .missionStartBlocked,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .string("reason", "cua_not_ready"),
                    .int("issue_count", self.cuaStatus.issues.count),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: requestedAt))
                ]),
                audit: .mission
            )
            lockFunctionalSurfaceForOnboarding()
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

        cursorSurface.collapseToCompact()
        pendingApproval = nil
        currentHermesSessionID = nil
        resetMissionProjection(goal: trimmedGoal)

        let snapshot = missionContextSnapshot(traceID: traceID)

        let envelope = Self.missionEnvelope(
            goal: trimmedGoal,
            contextSnapshot: snapshot,
            cuaStatus: cuaStatus
        )

        missionStatus = .running
        missionOutput = "Starting Hermes parent mission...\n"
        lastCommand = "./script/aura-hermes chat -Q --source aura -q <mission envelope>"
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
            try launchHermes(arguments: hermesChatArguments(
                query: envelope
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

    func approvePendingAction() async {
        let traceID = activeMissionTraceID ?? AURATelemetry.makeTraceID(prefix: "mission-approval")
        let startedAt = Date()
        AURATelemetry.info(
            .approvalContinueRequested,
            category: .approval,
            traceID: traceID,
            fields: missionFields([
                .string("operation", "approval_decision"),
                .string("tool_surface", Self.hermesToolSurfaceIdentifier)
            ]),
            audit: .approval
        )

        await refreshCuaStatus(traceID: traceID)
        guard cuaStatus.readyForHostControl else {
            AURATelemetry.warning(
                .approvalContinueBlocked,
                category: .approval,
                traceID: traceID,
                fields: missionFields([
                    .string("reason", "cua_not_ready"),
                    .int("issue_count", self.cuaStatus.issues.count)
                ]),
                audit: .approval
            )
            lockFunctionalSurfaceForOnboarding()
            blockAmbientEntryPoint()
            clearActiveMissionTrace()
            return
        }

        guard let pendingApproval else {
            AURATelemetry.warning(
                .approvalContinueIgnored,
                category: .approval,
                traceID: traceID,
                fields: missionFields([.string("reason", "no_pending_approval")]),
                audit: .approval
            )
            return
        }
        guard currentHermesSessionID?.isEmpty == false else {
            missionStatus = .failed
            missionOutput += "\n\nHermes requested approval but did not return a session_id, so AURA cannot safely resume the mission."
            lastOutput = missionOutput
            lastUpdated = Date()
            AURATelemetry.error(
                .approvalContinueBlocked,
                category: .approval,
                traceID: traceID,
                fields: missionFields([.string("reason", "missing_session_id")]),
                audit: .approval
            )
            clearActiveMissionTrace()
            return
        }

        cursorSurface.collapseToCompact()
        markApprovalWorkers(status: .running)
        let snapshot = ContextSnapshot.capture()
        contextSnapshot = snapshot
        logContextCaptured(snapshot, traceID: traceID)

        let envelope = Self.approvalContinuationEnvelope(
            approvedAction: pendingApproval.reason,
            originalGoal: missionGoal,
            contextSnapshot: snapshot,
            cuaStatus: cuaStatus
        )

        let resumeArguments = hermesChatArguments(
            query: envelope,
            resumeSessionID: currentHermesSessionID
        )

        self.pendingApproval = nil
        missionStatus = .running
        AURATelemetry.info(
            .approvalContinueLaunchHermes,
            category: .approval,
            traceID: traceID,
            fields: missionFields([
                .string("operation", "approval_result"),
                .int("approved_chars", pendingApproval.reason.count),
                .string("tool_surface", Self.hermesToolSurfaceIdentifier)
            ]),
            audit: .approval
        )
        appendMissionOutput("\n\nApproved one pending action. Resuming Hermes...\n")
        lastCommand = "./script/aura-hermes chat -Q --source aura --resume <session> -q <approval continuation>"

        do {
            try launchHermes(arguments: resumeArguments, environment: Self.hermesEnvironment(
                missionID: activeMissionID
            ), traceID: traceID)
        } catch {
            AURATelemetry.error(
                .approvalContinueLaunchFailed,
                category: .approval,
                traceID: traceID,
                fields: missionFields([
                    .string("error_type", String(describing: type(of: error))),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ]),
                audit: .approval
            )
            missionStatus = .failed
            missionOutput = error.localizedDescription
            lastOutput = missionOutput
            lastUpdated = Date()
            clearActiveMissionTrace()
        }
    }

    func denyPendingApproval() {
        let traceID = activeMissionTraceID ?? AURATelemetry.makeTraceID(prefix: "mission")
        cursorSurface.collapseToCompact()
        markActiveWorkers(status: .cancelled)
        pendingApproval = nil
        missionStatus = .cancelled
        AURATelemetry.info(
            .approvalDenied,
            category: .approval,
            traceID: traceID,
            fields: missionFields([.string("operation", "approval_decision")]),
            audit: .approval
        )
        appendMissionOutput("\n\nApproval denied. Mission stopped.")
        clearActiveMissionTrace()
    }

    func cancelMission() {
        guard let missionProcess, missionStatus == .running else { return }
        let traceID = activeMissionTraceID ?? AURATelemetry.makeTraceID(prefix: "mission")
        cursorSurface.collapseToCompact()
        markActiveWorkers(status: .cancelled)
        missionProcess.terminate()
        self.missionProcess = nil
        cancelMissionTimeout()
        pendingApproval = nil
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
        let command = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.sh)""#
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        lastCommand = "copy cua install command"
        lastOutput = "Copied Cua Driver install command:\n\(command)"
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

    func openHermesVoiceMode(
        autoEnable: Bool = true,
        traceID: String = AURATelemetry.makeTraceID(prefix: "voice")
    ) {
        let command = """
        cd \(Self.shellQuoted(AURAPaths.projectRoot.path))
        clear
        echo 'AURA project-local Hermes Voice Mode'
        echo 'Commands: /voice status, /voice on, /voice off, /voice tts'
        echo 'Record key defaults to Ctrl+B and is configurable at voice.record_key.'
        echo 'Local STT prefers faster-whisper when installed; no API key is required for that path.'
        echo
        ./script/aura-hermes
        """

        let enableCommand = autoEnable ? "\n            delay 1.5\n            do script \"/voice on\" in auraVoiceTab" : ""
        let script = """
        tell application "Terminal"
            activate
            set auraVoiceTab to do script \(Self.appleScriptString(command))\(enableCommand)
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.currentDirectoryURL = AURAPaths.projectRoot

        do {
            try process.run()
            lastCommand = "open Hermes voice mode"
            lastOutput = autoEnable
                ? "Opened project-local Hermes in Terminal and requested /voice on."
                : "Opened project-local Hermes in Terminal. Use /voice status, then /voice on when dependencies are present."
            lastUpdated = Date()
            AURATelemetry.info(
                .voiceModeOpenRequested,
                category: .ui,
                traceID: traceID,
                fields: [
                    .string("surface", "terminal"),
                    .bool("auto_enable", autoEnable)
                ],
                audit: .action
            )
        } catch {
            lastCommand = "open Hermes voice mode"
            lastOutput = "Could not open Terminal for Hermes Voice Mode: \(error.localizedDescription)"
            lastUpdated = Date()
            AURATelemetry.error(
                .voiceModeOpenFailed,
                category: .ui,
                traceID: traceID,
                fields: [.string("error_type", String(describing: type(of: error)))],
                audit: .action
            )
        }
    }

    func openArtifact(_ artifact: AURAArtifact) {
        guard artifact.exists else {
            missionOutput += "\n\nArtifact no longer exists at \(artifact.path)"
            lastOutput = missionOutput
            lastUpdated = Date()
            return
        }

        NSWorkspace.shared.open(artifact.url)
        AURATelemetry.info(
            .artifactOpened,
            category: .ui,
            fields: [
                .privateValue("path"),
                .string("artifact_type", artifact.type.rawValue)
            ],
            audit: .action
        )
    }

    func revealArtifact(_ artifact: AURAArtifact) {
        NSWorkspace.shared.activateFileViewerSelecting([artifact.url])
        AURATelemetry.info(
            .artifactRevealed,
            category: .ui,
            fields: [
                .privateValue("path"),
                .string("artifact_type", artifact.type.rawValue)
            ],
            audit: .action
        )
    }

    func continueWithArtifact(_ artifact: AURAArtifact) {
        missionGoal = "Continue from this artifact: \(artifact.path)"
        showAmbientEntryPoint()
        AURATelemetry.info(
            .artifactContinued,
            category: .ui,
            fields: [
                .privateValue("path"),
                .string("artifact_type", artifact.type.rawValue)
            ]
        )
    }

    private func startReadinessMonitor() {
        readinessMonitorTask?.cancel()
        readinessMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshPermissionStatusIfUnlocked()
            }
        }
    }

    private func refreshPermissionStatusIfUnlocked() async {
        guard cuaStatus.readyForHostControl
                || missionStatus == .running
                || missionStatus == .needsApproval
                || pendingApproval != nil else {
            return
        }

        await refreshPermissionStatus(
            traceID: activeMissionTraceID ?? AURATelemetry.makeTraceID(prefix: "cua-monitor"),
            telemetryEnabled: false
        )
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

        for line in chunk.components(separatedBy: .newlines) {
            extractMissionSignal(line)
            ingestArtifactCandidates(in: line)
        }
    }

    private func extractMissionSignal(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, let traceID = activeMissionTraceID else { return }

        let lowered = line.lowercased()
        let signalType: String
        if lowered.hasPrefix("error:")
            || lowered.hasPrefix("fatal:")
            || lowered.contains("traceback")
            || lowered.contains("exception:")
            || lowered.contains("non-zero exit")
            || lowered.contains("command failed") {
            signalType = "error_detected"
        } else if lowered.contains("delegate_task")
            || lowered.contains("delegating")
            || lowered.contains("spawn_agent") {
            signalType = "delegation"
        } else if lowered.contains("tool_call")
            || lowered.contains("calling tool")
            || lowered.contains("using tool")
            || lowered.contains("execute_tool") {
            signalType = "tool_call"
        } else if lowered.hasPrefix("status:")
            || lowered.hasPrefix("progress:")
            || lowered.hasPrefix("completed:") {
            signalType = "progress"
        } else {
            return
        }

        let fields = missionFields([
            .string("signal_type", signalType),
            .int("line_chars", line.count)
        ])

        if signalType == "error_detected" {
            updateMissionProjection(signalType: signalType, line: line)
            AURATelemetry.warning(
                .missionSignalDetected,
                category: .mission,
                traceID: traceID,
                fields: fields,
                audit: .mission
            )
        } else {
            updateMissionProjection(signalType: signalType, line: line)
            AURATelemetry.debug(
                .missionSignalDetected,
                category: .mission,
                traceID: traceID,
                fields: fields
            )
        }
    }

    private func resetMissionProjection(goal: String) {
        let now = Date()
        let parentID = activeMissionID ?? AURATelemetry.makeSpanID(prefix: "mission")
        workerRuns = [
            WorkerRun(
                id: parentID,
                title: "Hermes parent",
                status: .running,
                domain: .parent,
                detail: goal,
                startedAt: now,
                updatedAt: now,
                attachedApprovalID: nil,
                artifactIDs: []
            )
        ]
        artifacts = []
    }

    private func updateMissionProjection(signalType: String, line: String) {
        switch signalType {
        case "delegation":
            appendDerivedWorker(domain: .delegation, status: .running, title: "Delegated worker", detail: line)
        case "tool_call":
            appendDerivedWorker(domain: .tool, status: .running, title: Self.toolTitle(from: line), detail: line)
        case "progress":
            updateParentWorker(status: line.lowercased().hasPrefix("completed:") ? .completed : .running, detail: line)
        case "error_detected":
            appendDerivedWorker(domain: .progress, status: .failed, title: "Issue detected", detail: line)
        default:
            break
        }
    }

    private func appendDerivedWorker(domain: WorkerDomain, status: WorkerStatus, title: String, detail: String) {
        let normalizedDetail = Self.compactProjectionText(detail)

        if let index = workerRuns.indices.last(where: {
            workerRuns[$0].domain == domain
                && workerRuns[$0].title == title
                && workerRuns[$0].detail == normalizedDetail
        }) {
            workerRuns[index].status = status
            workerRuns[index].updatedAt = Date()
            return
        }

        let worker = WorkerRun(
            id: "\(activeMissionIDValue)-\(domain.rawValue)-\(workerRuns.count + 1)",
            title: title,
            status: status,
            domain: domain,
            detail: normalizedDetail,
            startedAt: Date(),
            updatedAt: Date(),
            attachedApprovalID: nil,
            artifactIDs: []
        )
        workerRuns.append(worker)

        if workerRuns.count > 12 {
            let parent = workerRuns.first
            workerRuns = Array(workerRuns.suffix(11))
            if let parent, !workerRuns.contains(where: { $0.id == parent.id }) {
                workerRuns.insert(parent, at: 0)
            }
        }
    }

    private func updateParentWorker(status: WorkerStatus, detail: String? = nil) {
        guard let index = workerRuns.firstIndex(where: { $0.domain == .parent }) else { return }
        workerRuns[index].status = status
        if let detail, !detail.isEmpty {
            workerRuns[index].detail = Self.compactProjectionText(detail)
        }
        workerRuns[index].updatedAt = Date()
    }

    private func markActiveWorkers(status: WorkerStatus) {
        for index in workerRuns.indices where workerRuns[index].status == .running || workerRuns[index].status == .queued || workerRuns[index].status == .needsApproval {
            workerRuns[index].status = status
            workerRuns[index].updatedAt = Date()
        }
    }

    private func markApprovalWorkers(status: WorkerStatus) {
        for index in workerRuns.indices where workerRuns[index].status == .needsApproval {
            workerRuns[index].status = status
            workerRuns[index].updatedAt = Date()
        }
    }

    private func attachApprovalToProjection(_ approval: ApprovalRequest) -> ApprovalRequest {
        let workerID: String
        if let index = workerRuns.indices.last(where: { workerRuns[$0].status == .running && workerRuns[$0].domain != .parent }) {
            workerID = workerRuns[index].id
            workerRuns[index].status = .needsApproval
            workerRuns[index].attachedApprovalID = approval.id
            workerRuns[index].updatedAt = Date()
        } else if let index = workerRuns.indices.first(where: { workerRuns[$0].domain == .parent }) {
            workerID = workerRuns[index].id
            workerRuns[index].status = .needsApproval
            workerRuns[index].attachedApprovalID = approval.id
            workerRuns[index].updatedAt = Date()
        } else {
            appendDerivedWorker(domain: .approval, status: .needsApproval, title: "Approval needed", detail: approval.reason)
            workerID = workerRuns.last?.id ?? activeMissionIDValue
        }

        return ApprovalRequest(
            id: approval.id,
            reason: approval.reason,
            requestedAt: approval.requestedAt,
            risk: Self.approvalRisk(from: approval.reason),
            target: Self.approvalTarget(from: approval.reason),
            scope: "one-time",
            attachedWorkerID: workerID
        )
    }

    private func ingestArtifactCandidates(in rawLine: String) {
        for path in Self.artifactPaths(in: rawLine) {
            let normalizedPath = Self.normalizedArtifactPath(path)
            guard !normalizedPath.isEmpty,
                  !artifacts.contains(where: { $0.path == normalizedPath }),
                  Self.isSafeArtifactPath(normalizedPath) else {
                continue
            }

            let ownerID = workerRuns.last(where: { $0.status == .running || $0.status == .completed })?.id
            let artifact = AURAArtifact(
                title: URL(fileURLWithPath: normalizedPath).lastPathComponent,
                path: normalizedPath,
                type: Self.artifactType(for: normalizedPath),
                owningWorkerID: ownerID,
                detectedAt: Date()
            )
            artifacts.append(artifact)

            if let ownerID,
               let index = workerRuns.firstIndex(where: { $0.id == ownerID }) {
                workerRuns[index].artifactIDs.append(artifact.id)
                workerRuns[index].updatedAt = Date()
            }

            AURATelemetry.info(
                .artifactDetected,
                category: .mission,
                traceID: activeMissionTraceID,
                fields: [
                    .string("artifact_type", artifact.type.rawValue),
                    .bool("exists", artifact.exists)
                ],
                audit: .action
            )
        }
    }

    private func hermesChatArguments(
        query: String,
        resumeSessionID: String? = nil
    ) -> [String] {
        var arguments = ["chat", "-Q", "--source", "aura"]

        if let resumeSessionID {
            arguments.append(contentsOf: ["--resume", resumeSessionID])
        }

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
        scheduleMissionTimeout(traceID: traceID)
    }

    private func finishMission(_ result: Result<HermesCommandResult, Error>) {
        if case .success(let commandResult) = result,
           timedOutMissionTraceID == commandResult.traceID {
            timedOutMissionTraceID = nil
            return
        }

        cancelMissionTimeout()
        missionProcess = nil

        switch result {
        case .success(let commandResult):
            let traceID = commandResult.traceID
            let output = commandResult.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedSessionID = Self.sessionID(in: output)
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

            if let approvalRequest = Self.approvalRequest(in: missionOutput) {
                if currentHermesSessionID?.isEmpty != false {
                    cursorSurface.collapseToCompact()
                    pendingApproval = nil
                    markActiveWorkers(status: .failed)
                    missionOutput += "\n\nHermes requested approval but did not return a session_id. AURA cannot resume this mission safely."
                    lastOutput = missionOutput
                    missionStatus = .failed
                    AURATelemetry.error(
                        .missionApprovalGateFailed,
                        category: .approval,
                        traceID: traceID,
                        fields: missionFields([
                            .string("reason", "missing_session_id"),
                            .int32("exit_code", commandResult.exitCode),
                            .int("hermes_duration_ms", commandResult.durationMilliseconds)
                        ]),
                        audit: .approval
                    )
                    clearActiveMissionTrace()
                } else {
                    cursorSurface.collapseToCompact()
                    let enrichedApproval = attachApprovalToProjection(approvalRequest)
                    pendingApproval = enrichedApproval
                    missionStatus = .needsApproval
                    logMissionRecoveryOutcomeIfNeeded(
                        traceID: traceID,
                        status: "needs_approval",
                        exitCode: commandResult.exitCode,
                        hermesDurationMilliseconds: commandResult.durationMilliseconds
                    )
                    AURATelemetry.info(
                        .missionPausedForApproval,
                        category: .approval,
                        traceID: traceID,
                        fields: missionFields([
                            .string("operation", "approval_intent"),
                            .int32("exit_code", commandResult.exitCode),
                            .int("approval_chars", approvalRequest.reason.count),
                            .int("hermes_duration_ms", commandResult.durationMilliseconds),
                            .int("output_chunks", self.missionOutputChunkCount)
                        ]),
                        audit: .approval
                    )
                }
            } else {
                if !commandResult.succeeded,
                   attemptMissionRecovery(from: commandResult, traceID: traceID) {
                    return
                }

                cursorSurface.collapseToCompact()
                pendingApproval = nil
                missionStatus = commandResult.succeeded ? .completed : .failed
                markActiveWorkers(status: commandResult.succeeded ? .completed : .failed)
                let missionDuration = activeMissionStartedAt.map { AURATelemetry.durationMilliseconds(from: $0, to: commandResult.finishedAt) } ?? commandResult.durationMilliseconds
                logMissionRecoveryOutcomeIfNeeded(
                    traceID: traceID,
                    status: commandResult.succeeded ? "succeeded" : "failed",
                    exitCode: commandResult.exitCode,
                    hermesDurationMilliseconds: commandResult.durationMilliseconds
                )
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
            }
        case .failure(let error):
            let traceID = activeMissionTraceID ?? AURATelemetry.makeTraceID(prefix: "mission")
            cursorSurface.collapseToCompact()
            pendingApproval = nil
            markActiveWorkers(status: .failed)
            missionStatus = .failed
            missionOutput = error.localizedDescription
            lastOutput = missionOutput
            lastUpdated = Date()
            if missionRetryCount > 0 {
                AURATelemetry.warning(
                    .missionRecoveryOutcome,
                    category: .mission,
                    traceID: traceID,
                    fields: missionFields([
                        .string("status", "failed"),
                        .int("retry_count", missionRetryCount),
                        .string("error_type", String(describing: type(of: error)))
                    ]),
                    audit: .mission
                )
            }
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

    private func scheduleMissionTimeout(traceID: String) {
        cancelMissionTimeout()
        missionTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.missionTimeoutSeconds * 1_000_000_000)
            } catch {
                return
            }

            await MainActor.run {
                guard let self,
                      self.missionStatus == .running,
                      let missionProcess = self.missionProcess
                else {
                    return
                }

                self.timedOutMissionTraceID = traceID
                missionProcess.terminate()
                self.missionProcess = nil
                self.pendingApproval = nil
                self.missionStatus = .failed
                self.markActiveWorkers(status: .failed)
                self.appendMissionOutput("\nMission timed out after \(Self.missionTimeoutSeconds) seconds and was stopped.")
                self.lastCommand = "mission timeout"
                self.lastOutput = self.missionOutput
                self.lastUpdated = Date()
                AURATelemetry.error(
                    .missionTimedOut,
                    category: .mission,
                    traceID: traceID,
                    fields: self.missionFields([
                        .int32("child_process_id", missionProcess.processIdentifier),
                        .int("timeout_seconds", Int(Self.missionTimeoutSeconds)),
                        .int("duration_ms", self.activeMissionStartedAt.map { AURATelemetry.durationMilliseconds(from: $0) } ?? 0)
                    ]),
                    audit: .mission
                )
                self.clearActiveMissionTrace()
            }
        }
    }

    private func cancelMissionTimeout() {
        missionTimeoutTask?.cancel()
        missionTimeoutTask = nil
    }

    private func attemptMissionRecovery(from commandResult: HermesCommandResult, traceID: String) -> Bool {
        guard missionStatus != .cancelled,
              missionRetryCount == 0,
              let sessionID = currentHermesSessionID,
              !sessionID.isEmpty else {
            return false
        }

        let diagnostic = Self.failureDiagnostic(
            exitCode: commandResult.exitCode,
            stderrTail: String(commandResult.errorOutput.suffix(1_200)),
            durationMilliseconds: commandResult.durationMilliseconds,
            outputChunks: missionOutputChunkCount
        )
        missionRetryCount += 1
        pendingApproval = nil
        missionStatus = .running
        lastCommand = "./script/aura-hermes chat -Q --source aura --resume <session> -q <failure recovery context>"

        AURATelemetry.info(
            .missionRecoveryAttempt,
            category: .mission,
            traceID: traceID,
            fields: missionFields([
                .int("retry_count", missionRetryCount),
                .int32("original_exit_code", commandResult.exitCode),
                .int("original_duration_ms", commandResult.durationMilliseconds),
                .int("stderr_bytes", commandResult.errorByteCount),
                .int("output_chunks", missionOutputChunkCount),
                .int("diagnostic_chars", diagnostic.count)
            ]),
            audit: .mission
        )
        appendMissionOutput("\n\nAURA detected the failed attempt and is asking Hermes to recover once.\n")

        do {
            try launchHermes(
                arguments: hermesChatArguments(
                    query: diagnostic,
                    resumeSessionID: sessionID
                ),
                environment: Self.hermesEnvironment(
                    missionID: activeMissionID
                ),
                traceID: traceID
            )
            return true
        } catch {
            missionStatus = .failed
            lastOutput = error.localizedDescription
            lastUpdated = Date()
            AURATelemetry.error(
                .missionRecoveryOutcome,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .string("status", "launch_failed"),
                    .int("retry_count", missionRetryCount),
                    .string("error_type", String(describing: type(of: error)))
                ]),
                audit: .mission
            )
            clearActiveMissionTrace()
            return true
        }
    }

    private func logMissionRecoveryOutcomeIfNeeded(
        traceID: String,
        status: String,
        exitCode: Int32,
        hermesDurationMilliseconds: Int
    ) {
        guard missionRetryCount > 0 else { return }

        let fields = missionFields([
            .string("status", status),
            .int("retry_count", missionRetryCount),
            .int32("exit_code", exitCode),
            .int("hermes_duration_ms", hermesDurationMilliseconds)
        ])

        if status == "succeeded" || status == "needs_approval" {
            AURATelemetry.info(
                .missionRecoveryOutcome,
                category: .mission,
                traceID: traceID,
                fields: fields,
                audit: .mission
            )
        } else {
            AURATelemetry.warning(
                .missionRecoveryOutcome,
                category: .mission,
                traceID: traceID,
                fields: fields,
                audit: .mission
            )
        }
    }

    private func blockAmbientEntryPoint() {
        AURATelemetry.warning(
            .functionalSurfaceBlocked,
            category: .ui,
            fields: [
                .bool("cua_ready", self.cuaStatus.readyForHostControl),
                .int("issue_count", self.cuaStatus.issues.count)
            ],
            audit: .governance
        )
        missionOutput = "AURA is locked until CUA setup is complete."
        lastCommand = "host-lane check"
        lastOutput = "\(missionOutput)\n\(readinessIssuesText())"
        lastUpdated = Date()
        updateCuaOnboardingMessage()
    }

    private func readinessIssuesText() -> String {
        cuaStatus.issues.joined(separator: " ")
    }

    private func syncHostControlAvailability() {
        let ready = cuaStatus.readyForHostControl
        if lastHostControlReady != ready {
            AURATelemetry.info(
                .hostControlStateChanged,
                category: .cua,
                fields: [
                    .bool("ready", ready),
                    .string("title", self.cuaStatus.title),
                    .int("issue_count", self.cuaStatus.issues.count)
                ],
                audit: .governance
            )
            lastHostControlReady = ready
        }

        if cuaStatus.readyForHostControl {
            globalHotKey.register()
        } else {
            globalHotKey.unregister()
            lockFunctionalSurfaceForOnboarding()
        }
        updateCursorIndicator()
    }

    private func updateCursorIndicator() {
        cursorSurface.setVisible(isAmbientEnabled && cuaStatus.readyForHostControl, store: self)
    }

    private func lockFunctionalSurfaceForOnboarding() {
        let traceID = activeMissionTraceID ?? AURATelemetry.makeTraceID(prefix: "host-lock")
        let hadActiveWork = missionProcess != nil
            || pendingApproval != nil
            || missionStatus == .running
            || missionStatus == .needsApproval

        if hadActiveWork {
            AURATelemetry.warning(
                .hostControlLock,
                category: .cua,
                traceID: traceID,
                fields: missionFields([
                    .bool("had_mission_process", self.missionProcess != nil),
                    .string("status", self.missionStatus.title)
                ]),
                audit: .governance
            )
        } else {
            AURATelemetry.debug(
                .hostControlLockIdle,
                category: .cua,
                traceID: traceID,
                fields: missionFields([.string("status", self.missionStatus.title)])
            )
        }
        cursorSurface.hide()
        isShortcutPulseActive = false

        if let missionProcess {
            missionProcess.terminate()
            self.missionProcess = nil
        }

        if pendingApproval != nil || missionStatus == .running || missionStatus == .needsApproval {
            pendingApproval = nil
            currentHermesSessionID = nil
            missionStatus = .cancelled
            missionOutput = "AURA locked because CUA setup is incomplete."
            lastCommand = "host-lane lock"
            lastOutput = missionOutput
            lastUpdated = Date()
        }
    }

    private func clearActiveMissionTrace() {
        cancelMissionTimeout()
        activeMissionTraceID = nil
        activeMissionID = nil
        activeMissionStartedAt = nil
        missionOutputChunkCount = 0
        missionRetryCount = 0
    }

    private static func missionEnvelope(
        goal: String,
        contextSnapshot: ContextSnapshot,
        cuaStatus: CuaDriverStatus
    ) -> String {
        return """
        AURA MISSION ENVELOPE

        You are Hermes Agent acting as AURA's parent mission orchestrator. AURA is only the native Mac cockpit. You own orchestration, planning, tool routing, configured approvals, background agents, and final synthesis.

        USER GOAL
        \(goal)

        CURRENT MAC CONTEXT
        \(contextSnapshot.markdownSummary)

        HERMES CONFIG AND TOOL SURFACE
        - Tool availability, MCP exposure, command approvals, provider setup, and voice configuration are owned by project-local Hermes config at .aura/hermes-home/config.yaml.
        - AURA does not choose Hermes toolsets for this mission and never uses global Hermes.
        - Use the tools Hermes exposes to you. If a required tool is unavailable, explain the missing Hermes config/setup step.
        - CUA readiness: \(cuaStatus.title)
        - CUA is exposed through AURA's daemon-backed MCP transport proxy when registered in Hermes config.
        - Never request macOS permissions from workflow. Do not call check_permissions with prompt:true. If CUA reports missing permissions, stop; AURA must return to onboarding.

        ORCHESTRATION RULES
        - Use delegate_task for background workers when it materially helps.
        - Do not ask AURA to split the mission into subagents; you decide when to delegate.
        - Subagents start with fresh context. Pass every subagent a complete goal, relevant context, constraints, and expected summary.
        - Keep delegation flat for now: up to 3 concurrent children, no nested orchestrator children.
        - Use CUA read/snapshot tools when the user asks about the current Mac screen or app state.

        SAFETY HARD STOPS
        Return exactly "NEEDS_APPROVAL: <reason and proposed next action>" and stop before any action blocked by Hermes config, external send, posting, purchase, credential-sensitive action, financial action, regulated advice/action, or unrelated foreground takeover.
        Drafting is allowed. Sending or posting is not.
        Do not copy protected creator content. Transform/adapt patterns into original work.

        OUTPUT CONTRACT
        - Start with a concise status line.
        - Use background delegation when useful, then synthesize child summaries.
        - End with one final packet: outcome, artifacts/paths if any, sources if researched, blocked approvals if any, and recommended next action.
        """
    }

    private static func approvalSafetyHardStops() -> String {
        "Even after this approval, stop before any external send, posting, purchase, credential-sensitive action, financial action, regulated advice/action, unrelated foreground takeover, or destructive action outside the approved scope."
    }

    private static func approvalContinuationEnvelope(
        approvedAction: String,
        originalGoal: String,
        contextSnapshot: ContextSnapshot,
        cuaStatus: CuaDriverStatus
    ) -> String {
        return """
        AURA APPROVAL CONTINUATION

        Continue the same AURA mission in this Hermes session.

        ORIGINAL USER GOAL
        \(originalGoal)

        USER APPROVAL
        The user approved exactly this pending action:
        \(approvedAction)

        This is not broad approval. Execute only the approved action needed to continue the mission, then continue normally. If another blocked action is needed, return exactly "NEEDS_APPROVAL: <reason and proposed next action>" and stop again.

        CURRENT MAC CONTEXT
        \(contextSnapshot.markdownSummary)

        HERMES CONFIG AND TOOL SURFACE
        - Tool availability, MCP exposure, command approvals, and provider setup remain owned by project-local Hermes config.
        - AURA does not choose Hermes toolsets for this continuation.
        - CUA readiness: \(cuaStatus.title)
        - CUA is exposed through AURA's daemon-backed MCP transport proxy when registered in Hermes config.
        - Never request macOS permissions from workflow. If CUA reports missing permissions, stop; AURA must return to onboarding.

        SAFETY HARD STOPS
        \(approvalSafetyHardStops())

        OUTPUT CONTRACT
        Continue with concise progress and end with outcome, artifacts/paths if any, blocked approvals if any, and recommended next action.
        """
    }

    private static func failureDiagnostic(
        exitCode: Int32,
        stderrTail: String,
        durationMilliseconds: Int,
        outputChunks: Int
    ) -> String {
        let trimmedError = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeError = trimmedError.isEmpty ? "No stderr was captured." : trimmedError

        return """
        AURA RECOVERY CONTEXT

        The previous attempt in this mission failed before completion.

        EXIT CODE: \(exitCode)
        DURATION: \(durationMilliseconds)ms
        OUTPUT CHUNKS: \(outputChunks)

        LAST ERROR OUTPUT:
        \(safeError)

        INSTRUCTIONS:
        Diagnose what went wrong from this bounded error tail. Do not repeat the same approach. Try one alternative strategy that still respects the AURA mission envelope and Hermes-configured approvals. If the task is impossible or needs user approval, say so clearly.
        """
    }

    private static func compactProjectionText(_ text: String, limit: Int = 160) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard normalized.count > limit else { return normalized }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: max(0, limit - 3))
        return String(normalized[..<endIndex]) + "..."
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private static func toolTitle(from line: String) -> String {
        let lowered = line.lowercased()
        let markers = ["calling tool", "using tool", "tool_call", "execute_tool"]

        for marker in markers {
            guard let range = lowered.range(of: marker) else { continue }
            let suffix = line[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: ": -_"))
            if let first = suffix.components(separatedBy: .whitespacesAndNewlines).first,
               !first.isEmpty {
                return "Tool: \(first)"
            }
        }

        return "Tool call"
    }

    private static func approvalRisk(from reason: String) -> String {
        let lower = reason.lowercased()
        if lower.contains("send") || lower.contains("post") || lower.contains("message") || lower.contains("email") {
            return "external send"
        }
        if lower.contains("delete") || lower.contains("remove") || lower.contains("overwrite") {
            return "destructive local change"
        }
        if lower.contains("credential") || lower.contains("password") || lower.contains("token") {
            return "credential-sensitive"
        }
        if lower.contains("purchase") || lower.contains("payment") || lower.contains("buy") {
            return "purchase"
        }
        return "local action"
    }

    private static func approvalTarget(from reason: String) -> String? {
        let markers = [" at ", " to ", " in ", " on "]
        for marker in markers {
            guard let range = reason.lowercased().range(of: marker) else { continue }
            let suffix = reason[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !suffix.isEmpty else { continue }
            return compactProjectionText(suffix, limit: 80)
        }
        return nil
    }

    private static func artifactPaths(in rawLine: String) -> [String] {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return [] }

        let pattern = #"(?:(?:~|/)[^\s,;]+|(?:artifacts|artifact|dist|reports|outputs|build|docs|Sources)/[^\s,;]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: line) else { return nil }
            return cleanArtifactPath(String(line[matchRange]))
        }
    }

    private static func cleanArtifactPath(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.,;:)]}"))
    }

    private static func normalizedArtifactPath(_ path: String) -> String {
        let cleaned = cleanArtifactPath(path)
        guard !cleaned.isEmpty else { return "" }

        if cleaned.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return home + "/" + String(cleaned.dropFirst(2))
        }

        if cleaned.hasPrefix("/") {
            return cleaned
        }

        return AURAPaths.projectRoot
            .appendingPathComponent(cleaned, isDirectory: false)
            .standardizedFileURL
            .path
    }

    private static func isSafeArtifactPath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let projectRoot = AURAPaths.projectRoot.standardizedFileURL.path

        if standardized.contains("/.aura/")
            || standardized.contains("/.build/")
            || standardized.contains("/.swiftpm/")
            || standardized.contains("/node_modules/")
            || standardized.contains("/Library/Logs/") {
            return false
        }

        return standardized.hasPrefix(projectRoot)
            || standardized.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path)
    }

    private static func artifactType(for path: String) -> AURAArtifactType {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return path.hasSuffix(".app") ? .app : .folder
        }

        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "app":
            return .app
        case "csv", "tsv", "xlsx", "xls", "json":
            return .table
        case "md", "pdf", "docx", "txt", "html":
            return .report
        case "":
            return .unknown
        default:
            return .file
        }
    }

    private static func approvalRequest(in output: String) -> ApprovalRequest? {
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            guard let range = lowercased.range(of: "needs_approval:") else { continue }

            let reason = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return ApprovalRequest(reason: reason, requestedAt: Date())
        }

        return nil
    }

    private static func sessionID(in output: String) -> String? {
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.lowercased().hasPrefix("session_id:") else { continue }

            return line
                .dropFirst("session_id:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        return nil
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
