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
    @Published var automationPolicy: GlobalAutomationPolicy {
        didSet {
            UserDefaults.standard.set(automationPolicy.rawValue, forKey: Self.automationPolicyKey)
            AURATelemetry.info(
                .automationPolicyChanged,
                category: .ui,
                fields: [.string("policy", self.automationPolicy.rawValue)],
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
    private let cursorIndicator = CursorIndicatorController()
    private let ambientMissionPanel = AmbientMissionPanelController()
    private lazy var globalHotKey = GlobalHotKeyController { [weak self] in
        self?.showAmbientEntryPoint()
    }
    private var missionProcess: Process?
    private var readinessMonitorTask: Task<Void, Never>?
    private var didRunLaunchOnboarding = false
    private var activeMissionTraceID: String?
    private var activeMissionID: String?
    private var activeMissionStartedAt: Date?
    private var missionOutputChunkCount = 0
    private var missionRetryCount = 0
    private var lastHostControlReady: Bool?
    private static let automationPolicyKey = "AURAAutomationPolicy"

    private var activeMissionIDValue: String {
        activeMissionID ?? "none"
    }

    private func missionFields(_ fields: [AURATelemetry.Field] = []) -> [AURATelemetry.Field] {
        [.string("mission_id", activeMissionIDValue)] + fields
    }

    init() {
        let storedPolicy = UserDefaults.standard.string(forKey: Self.automationPolicyKey)
        automationPolicy = GlobalAutomationPolicy(rawValue: storedPolicy ?? "") ?? .readOnly
        updateCursorIndicator()
        syncHostControlAvailability()
        startReadinessMonitor()
        AURATelemetry.info(
            .storeInitialized,
            category: .mission,
            fields: [.string("policy", self.automationPolicy.rawValue)],
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
            && automationPolicy != .readOnly
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

    func triggerAmbientShortcut() {
        guard canOpenAmbientEntryPoint else {
            AURATelemetry.warning(
                .ambientShortcutBlocked,
                category: .ui,
                fields: [
                    .bool("cua_ready", self.cuaStatus.readyForHostControl),
                    .bool("onboarding", self.isRunningCuaOnboarding)
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
                .bool("has_pending_approval", self.pendingApproval != nil)
            ]
        )
        captureContext(traceID: traceID)
        isShortcutPulseActive = true
        updateCursorIndicator()

        if missionStatus != .running && pendingApproval == nil {
            missionOutput = "Ambient panel opened. Type or dictate the mission goal, then start Hermes."
            lastCommand = "ambient shortcut"
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
                    .bool("onboarding", self.isRunningCuaOnboarding)
                ],
                audit: .governance
            )
            blockAmbientEntryPoint()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let traceID = AURATelemetry.makeTraceID(prefix: "panel")
        AURATelemetry.info(
            .ambientPanelOpenRequested,
            category: .ui,
            traceID: traceID,
            fields: [
                .string("status", self.missionStatus.title),
                .bool("has_pending_approval", self.pendingApproval != nil)
            ]
        )

        if pendingApproval != nil || missionStatus == .running {
            if !isAmbientEnabled {
                isAmbientEnabled = true
            }
            captureContext(traceID: traceID)
            updateCursorIndicator()
        } else {
            triggerAmbientShortcut()
        }

        ambientMissionPanel.show(store: self)
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
            proxyPath,
            "--env",
            "AURA_AUTOMATION_POLICY=${AURA_AUTOMATION_POLICY}",
            "AURA_CUA_ALLOW_ACTIONS=${AURA_CUA_ALLOW_ACTIONS}"
        ], traceID: traceID) { [weak self] result in
            if result.succeeded {
                self?.lastOutput = "Registered Cua Driver MCP through AURA's daemon proxy.\n\n\(result.combinedOutput)"
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
                .string("policy", self.automationPolicy.rawValue),
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

        pendingApproval = nil
        currentHermesSessionID = nil

        let snapshot = missionContextSnapshot(traceID: traceID)

        let toolsets = Self.hermesToolsets(for: automationPolicy)
        let envelope = Self.missionEnvelope(
            goal: trimmedGoal,
            automationPolicy: automationPolicy,
            contextSnapshot: snapshot,
            cuaStatus: cuaStatus,
            exposedToolsets: toolsets
        )

        missionStatus = .running
        missionOutput = "Starting Hermes parent mission...\n"
        lastCommand = "./script/aura-hermes chat -Q --source aura -t \(toolsets.joined(separator: ",")) -q <mission envelope>"
        lastOutput = missionOutput
        lastUpdated = Date()

        do {
            AURATelemetry.info(
                .missionLaunchHermes,
                category: .mission,
                traceID: traceID,
                fields: missionFields([
                    .string("operation", "invoke_agent"),
                    .string("toolsets", toolsets.joined(separator: ","))
                ]),
                audit: .agent
            )
            try launchHermes(arguments: hermesChatArguments(
                query: envelope,
                toolsets: toolsets
            ), environment: Self.hermesEnvironment(
                for: automationPolicy,
                cuaActionsAllowed: automationPolicy == .writeAlways,
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
                .string("policy", self.automationPolicy.rawValue)
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

        guard automationPolicy != .readOnly else {
            AURATelemetry.warning(
                .approvalContinueBlocked,
                category: .approval,
                traceID: traceID,
                fields: missionFields([.string("reason", "read_only_policy")]),
                audit: .approval
            )
            missionStatus = .needsApproval
            missionOutput += "\n\nRead Only mode blocks this action. Change the global automation policy to Ask Per Task or Always Allow before continuing."
            lastOutput = missionOutput
            lastUpdated = Date()
            return
        }

        let snapshot = ContextSnapshot.capture()
        contextSnapshot = snapshot
        logContextCaptured(snapshot, traceID: traceID)

        let toolsets = Self.hermesToolsets(for: automationPolicy)
        let envelope = Self.approvalContinuationEnvelope(
            approvedAction: pendingApproval.reason,
            originalGoal: missionGoal,
            automationPolicy: automationPolicy,
            contextSnapshot: snapshot,
            cuaStatus: cuaStatus,
            exposedToolsets: toolsets
        )

        let resumeArguments = hermesChatArguments(
            query: envelope,
            resumeSessionID: currentHermesSessionID,
            toolsets: toolsets
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
                .string("toolsets", toolsets.joined(separator: ","))
            ]),
            audit: .approval
        )
        appendMissionOutput("\n\nApproved one pending action. Resuming Hermes...\n")
        lastCommand = "./script/aura-hermes chat -Q --source aura --resume <session> -t \(toolsets.joined(separator: ",")) -q <approval continuation>"

        do {
            try launchHermes(arguments: resumeArguments, environment: Self.hermesEnvironment(
                for: automationPolicy,
                cuaActionsAllowed: automationPolicy != .readOnly,
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
        missionProcess.terminate()
        self.missionProcess = nil
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
            AURATelemetry.warning(
                .missionSignalDetected,
                category: .mission,
                traceID: traceID,
                fields: fields,
                audit: .mission
            )
        } else {
            AURATelemetry.debug(
                .missionSignalDetected,
                category: .mission,
                traceID: traceID,
                fields: fields
            )
        }
    }

    private func hermesChatArguments(
        query: String,
        resumeSessionID: String? = nil,
        toolsets: [String]
    ) -> [String] {
        var arguments = ["chat", "-Q", "--source", "aura"]

        if let resumeSessionID {
            arguments.append(contentsOf: ["--resume", resumeSessionID])
        }

        arguments.append(contentsOf: ["-t", toolsets.joined(separator: ",")])
        arguments.append(contentsOf: ["-q", query])
        return arguments
    }

    private static func hermesToolsets(for automationPolicy: GlobalAutomationPolicy) -> [String] {
        switch automationPolicy {
        case .readOnly, .writePerTask:
            return [
                "web",
                "skills",
                "todo",
                "memory",
                "session_search",
                "clarify",
                "delegation",
                "cua-driver"
            ]
        case .writeAlways:
            return [
                "web",
                "browser",
                "terminal",
                "file",
                "code_execution",
                "skills",
                "todo",
                "memory",
                "session_search",
                "clarify",
                "delegation",
                "cua-driver"
            ]
        }
    }

    private static func hermesEnvironment(
        for automationPolicy: GlobalAutomationPolicy,
        cuaActionsAllowed: Bool,
        missionID: String?
    ) -> [String: String] {
        [
            "AURA_AUTOMATION_POLICY": automationPolicy.rawValue,
            "AURA_CUA_ALLOW_ACTIONS": cuaActionsAllowed ? "1" : "0",
            "AURA_MISSION_ID": missionID ?? "none"
        ]
    }

    private func launchHermes(arguments: [String], environment: [String: String], traceID: String) throws {
        missionProcess = try hermesService.start(
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
    }

    private func finishMission(_ result: Result<HermesCommandResult, Error>) {
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
                    pendingApproval = nil
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
                    pendingApproval = approvalRequest
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

                pendingApproval = nil
                missionStatus = commandResult.succeeded ? .completed : .failed
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
            pendingApproval = nil
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
        let toolsets = Self.hermesToolsets(for: automationPolicy)
        missionRetryCount += 1
        pendingApproval = nil
        missionStatus = .running
        lastCommand = "./script/aura-hermes chat -Q --source aura --resume <session> -t \(toolsets.joined(separator: ",")) -q <failure recovery context>"

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
                    resumeSessionID: sessionID,
                    toolsets: toolsets
                ),
                environment: Self.hermesEnvironment(
                    for: automationPolicy,
                    cuaActionsAllowed: automationPolicy == .writeAlways,
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
        cursorIndicator.setVisible(isAmbientEnabled && cuaStatus.readyForHostControl)
        cursorIndicator.update(
            status: missionStatus,
            isShortcutActive: isShortcutPulseActive,
            missionOutput: missionOutput,
            pendingApprovalTitle: pendingApproval?.title,
            automationPolicyTitle: automationPolicy.title
        )
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
        ambientMissionPanel.hide()
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
        activeMissionTraceID = nil
        activeMissionID = nil
        activeMissionStartedAt = nil
        missionOutputChunkCount = 0
        missionRetryCount = 0
    }

    private static func missionEnvelope(
        goal: String,
        automationPolicy: GlobalAutomationPolicy,
        contextSnapshot: ContextSnapshot,
        cuaStatus: CuaDriverStatus,
        exposedToolsets: [String]
    ) -> String {
        let localActionRule: String

        switch automationPolicy {
        case .readOnly:
            localActionRule = "Read-only. You may analyze, research, plan, draft text, and use CUA read/snapshot tools to inspect the Mac. Do not write files, modify repositories, run state-changing terminal commands, use CUA action tools, click, type, send, post, purchase, delete, or move anything."
        case .writePerTask:
            localActionRule = "Ask per task. You may analyze, research, plan, draft text, and use CUA read/snapshot tools now. Before any local file write, repository edit, state-changing terminal command, CUA action tool, foreground click/type, or app workflow action, return NEEDS_APPROVAL with the exact proposed task and stop."
        case .writeAlways:
            localActionRule = "Always allow local writes and host control. You may perform non-destructive local file edits, state-changing terminal work, and CUA computer-use actions when useful. Still stop for destructive, credential-sensitive, external-send, posting, purchase, or financial actions."
        }

        return """
        AURA MISSION ENVELOPE

        You are Hermes Agent acting as AURA's parent mission orchestrator. AURA is only the native Mac cockpit. You own orchestration, planning, tool routing, background agents, and final synthesis.

        USER GOAL
        \(goal)

        CURRENT MAC CONTEXT
        \(contextSnapshot.markdownSummary)

        GLOBAL AUTOMATION POLICY
        - Policy: \(automationPolicy.title)
        - Summary: \(automationPolicy.summary)
        - Local action rule: \(localActionRule)
        - CUA readiness: \(cuaStatus.title)
        - CUA host-control allowed now: \(automationPolicy == .writeAlways ? "yes" : "read/snapshot only")
        - Exposed Hermes toolsets: \(exposedToolsets.joined(separator: ", "))
        - CUA is exposed through AURA's daemon-backed MCP proxy. Never request macOS permissions from workflow.

        ORCHESTRATION RULES
        - Use delegate_task for background workers when it materially helps.
        - Do not ask AURA to split the mission into subagents; you decide when to delegate.
        - Subagents start with fresh context. Pass every subagent a complete goal, relevant context, constraints, and expected summary.
        - Keep delegation flat for now: up to 3 concurrent children, no nested orchestrator children.
        - Suggested subagent toolsets: ["web"] for research, ["terminal", "file"] for repo/file/build work, ["terminal", "file", "web"] for full-stack work.
        - Use CUA read/snapshot tools when the user asks about the current Mac screen or app state.
        - Do not call check_permissions with prompt:true. If CUA reports missing permissions, stop; AURA must return to onboarding.

        SAFETY HARD STOPS
        Return exactly "NEEDS_APPROVAL: <reason and proposed next action>" and stop before any action blocked by the global automation policy, external send, posting, purchase, destructive file operation, credential-sensitive action, financial action, or foreground takeover not explicitly allowed above.
        Drafting is allowed. Sending or posting is not.
        Do not copy protected creator content. Transform/adapt patterns into original work.

        OUTPUT CONTRACT
        - Start with a concise status line.
        - Use background delegation when useful, then synthesize child summaries.
        - End with one final packet: outcome, artifacts/paths if any, sources if researched, blocked approvals if any, and recommended next action.
        """
    }

    private static func approvalContinuationEnvelope(
        approvedAction: String,
        originalGoal: String,
        automationPolicy: GlobalAutomationPolicy,
        contextSnapshot: ContextSnapshot,
        cuaStatus: CuaDriverStatus,
        exposedToolsets: [String]
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

        GLOBAL AUTOMATION POLICY
        - Policy: \(automationPolicy.title)
        - Summary: \(automationPolicy.summary)
        - CUA readiness: \(cuaStatus.title)
        - CUA host-control allowed for this approved action when needed: yes
        - Exposed Hermes toolsets: \(exposedToolsets.joined(separator: ", "))
        - CUA is exposed through AURA's daemon-backed MCP proxy. Never request macOS permissions from workflow.

        SAFETY HARD STOPS
        Even after this approval, stop before any external send, posting, purchase, destructive file operation, credential-sensitive action, financial action, or unrelated foreground takeover.

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
        Diagnose what went wrong from this bounded error tail. Do not repeat the same approach. Try one alternative strategy that still respects the AURA mission envelope and approval policy. If the task is impossible or needs user approval, say so clearly.
        """
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
