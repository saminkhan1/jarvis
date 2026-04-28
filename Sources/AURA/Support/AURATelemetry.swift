import Foundation
import OSLog

enum AURATelemetry {
    static let schemaVersion = 1
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.wexprolabs.aura"
    static let appSessionID = ProcessInfo.processInfo.environment["AURA_APP_SESSION_ID"] ?? UUID().uuidString
    static let processID = ProcessInfo.processInfo.processIdentifier

    enum Category: String {
        case app = "App"
        case launch = "Launch"
        case ui = "UI"
        case hotKey = "HotKey"
        case mission = "Mission"
        case approval = "Approval"
        case hermes = "Hermes"
        case cua = "CUA"
        case process = "Process"
    }

    enum Severity: String {
        case debug
        case info
        case warning
        case error
    }

    enum AuditKind: String {
        case lifecycle
        case mission
        case approval
        case governance
        case agent
        case action
    }

    enum Event: String, CaseIterable {
        case ambientIndicatorToggled = "ambient_indicator_toggled"
        case ambientPanelBlocked = "ambient_panel_blocked"
        case ambientPanelCreated = "ambient_panel_created"
        case ambientPanelHidden = "ambient_panel_hidden"
        case ambientPanelOpenRequested = "ambient_panel_open_requested"
        case ambientPanelShown = "ambient_panel_shown"
        case ambientShortcutBlocked = "ambient_shortcut_blocked"
        case ambientShortcutOpen = "ambient_shortcut_open"
        case appDidFinishLaunching = "app_did_finish_launching"
        case appWillFinishLaunching = "app_will_finish_launching"
        case approvalContinueBlocked = "approval_continue_blocked"
        case approvalContinueIgnored = "approval_continue_ignored"
        case approvalContinueLaunchFailed = "approval_continue_launch_failed"
        case approvalContinueLaunchHermes = "approval_continue_launch_hermes"
        case approvalContinueRequested = "approval_continue_requested"
        case approvalDenied = "approval_denied"
        case contextCaptured = "context_captured"
        case contextReused = "context_reused"
        case cuaDaemonCommandCopied = "cua_daemon_command_copied"
        case cuaDaemonRestartCommandFinish = "cua_daemon_restart_command_finish"
        case cuaDaemonStartBlocked = "cua_daemon_start_blocked"
        case cuaDaemonStartCommandFinish = "cua_daemon_start_command_finish"
        case cuaDaemonStartFinish = "cua_daemon_start_finish"
        case cuaDaemonStartIgnored = "cua_daemon_start_ignored"
        case cuaDaemonStartRequested = "cua_daemon_start_requested"
        case cuaDaemonStartSkipped = "cua_daemon_start_skipped"
        case cuaDaemonStartUI = "cua_daemon_start_ui"
        case cuaDaemonStartUIFinish = "cua_daemon_start_ui_finish"
        case cuaInstallCommandCopied = "cua_install_command_copied"
        case cuaComputerUseEnableBlocked = "cua_computer_use_enable_blocked"
        case cuaComputerUseEnableFinish = "cua_computer_use_enable_finish"
        case cuaComputerUseEnableStart = "cua_computer_use_enable_start"
        case cuaOnboardingProgress = "cua_onboarding_progress"
        case cuaPermissionsPromptCommandFinish = "cua_permissions_prompt_command_finish"
        case cuaPermissionsRequestBlocked = "cua_permissions_request_blocked"
        case cuaPermissionsRequestFinish = "cua_permissions_request_finish"
        case cuaPermissionsRequestIgnored = "cua_permissions_request_ignored"
        case cuaPermissionsRequestStart = "cua_permissions_request_start"
        case cuaPermissionsRequestUI = "cua_permissions_request_ui"
        case cuaPermissionsRequestUIFinish = "cua_permissions_request_ui_finish"
        case cuaPrepareFinish = "cua_prepare_finish"
        case cuaPrepareStart = "cua_prepare_start"
        case cuaRefreshFinish = "cua_refresh_finish"
        case cuaRefreshSkipped = "cua_refresh_skipped"
        case cuaRefreshStart = "cua_refresh_start"
        case cuaStatusFinish = "cua_status_finish"
        case cuaStatusStart = "cua_status_start"
        case cursorIndicatorVisibilityChanged = "cursor_indicator_visibility_changed"
        case functionalSurfaceBlocked = "functional_surface_blocked"
        case hermesCommandFinish = "hermes_command_finish"
        case hermesCommandStart = "hermes_command_start"
        case hermesProcessLaunchError = "hermes_process_launch_error"
        case hermesSessionCaptured = "hermes_session_captured"
        case hermesSessionsRefreshed = "hermes_sessions_refreshed"
        case hermesStreamFinish = "hermes_stream_finish"
        case hermesStreamLaunchError = "hermes_stream_launch_error"
        case hermesStreamStart = "hermes_stream_start"
        case hermesUICommandFailed = "hermes_ui_command_failed"
        case hermesUICommandFinish = "hermes_ui_command_finish"
        case hermesUICommandStart = "hermes_ui_command_start"
        case hermesWrapperExec = "hermes_wrapper_exec"
        case hermesWrapperMissing = "hermes_wrapper_missing"
        case hermesWrapperMissingPython = "hermes_wrapper_missing_python"
        case hermesWrapperQuietFinish = "hermes_wrapper_quiet_finish"
        case hermesWrapperQuietStart = "hermes_wrapper_quiet_start"
        case hostControlLock = "host_control_lock"
        case hostControlLockIdle = "host_control_lock_idle"
        case hostControlStateChanged = "host_control_state_changed"
        case hotkeyEventHandlerInstalled = "hotkey_event_handler_installed"
        case hotkeyPressedGlobal = "hotkey_pressed_global"
        case hotkeyPressedLocal = "hotkey_pressed_local"
        case hotkeyRegisterFailed = "hotkey_register_failed"
        case hotkeyRegistered = "hotkey_registered"
        case hotkeyUnregistered = "hotkey_unregistered"
        case launchOnboardingFinish = "launch_onboarding_finish"
        case launchOnboardingStart = "launch_onboarding_start"
        case macPrivacySettingsOpen = "mac_privacy_settings_open"
        case mainWindowActivated = "main_window_activated"
        case missionApprovalGateFailed = "mission_approval_gate_failed"
        case missionCancelledByUser = "mission_cancelled_by_user"
        case missionFinish = "mission_finish"
        case missionFinishAfterCancel = "mission_finish_after_cancel"
        case missionFinishFailed = "mission_finish_failed"
        case missionLaunchFailed = "mission_launch_failed"
        case missionLaunchHermes = "mission_launch_hermes"
        case missionInputModeChanged = "mission_input_mode_changed"
        case missionOutputChunk = "mission_output_chunk"
        case missionPausedForApproval = "mission_paused_for_approval"
        case missionRecoveryAttempt = "mission_recovery_attempt"
        case missionRecoveryOutcome = "mission_recovery_outcome"
        case missionStartBlocked = "mission_start_blocked"
        case missionStartIgnored = "mission_start_ignored"
        case missionStartRequested = "mission_start_requested"
        case missionTimedOut = "mission_timed_out"
        case projectFolderOpened = "project_folder_opened"
        case refreshAllFinish = "refresh_all_finish"
        case refreshAllStart = "refresh_all_start"
        case setupCommandCopied = "setup_command_copied"
        case shellCommandFinish = "shell_command_finish"
        case shellCommandStart = "shell_command_start"
        case shellCommandTimeout = "shell_command_timeout"
        case shellProcessLaunchError = "shell_process_launch_error"
        case storeInitialized = "store_initialized"
        case voiceInputCancelled = "voice_input_cancelled"
        case voiceInputPermissionDenied = "voice_input_permission_denied"
        case voiceInputRecordStart = "voice_input_record_start"
        case voiceInputRecordStop = "voice_input_record_stop"
        case voiceInputTranscribeFailed = "voice_input_transcribe_failed"
        case voiceInputTranscribeFinish = "voice_input_transcribe_finish"
        case xcodeRedirectFailed = "xcode_redirect_failed"
        case xcodeRedirectSkipped = "xcode_redirect_skipped"
        case xcodeRedirectSuccess = "xcode_redirect_success"
    }

    struct Field {
        let key: String
        let value: Any
        let includeInAudit: Bool

        static func string(_ key: String, _ value: String, audit: Bool = true) -> Field {
            Field(key: key, value: value, includeInAudit: audit)
        }

        static func int(_ key: String, _ value: Int, audit: Bool = true) -> Field {
            Field(key: key, value: value, includeInAudit: audit)
        }

        static func int32(_ key: String, _ value: Int32, audit: Bool = true) -> Field {
            Field(key: key, value: Int(value), includeInAudit: audit)
        }

        static func bool(_ key: String, _ value: Bool, audit: Bool = true) -> Field {
            Field(key: key, value: value, includeInAudit: audit)
        }

        static func privateValue(_ key: String) -> Field {
            Field(key: key, value: "<private>", includeInAudit: false)
        }
    }

    static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    static func debug(
        _ event: Event,
        category: Category,
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        fields: [Field] = [],
        audit: AuditKind? = nil
    ) {
        log(event, category: category, severity: .debug, traceID: traceID, spanID: spanID, parentSpanID: parentSpanID, fields: fields, audit: audit)
    }

    static func info(
        _ event: Event,
        category: Category,
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        fields: [Field] = [],
        audit: AuditKind? = nil
    ) {
        log(event, category: category, severity: .info, traceID: traceID, spanID: spanID, parentSpanID: parentSpanID, fields: fields, audit: audit)
    }

    static func warning(
        _ event: Event,
        category: Category,
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        fields: [Field] = [],
        audit: AuditKind? = nil
    ) {
        log(event, category: category, severity: .warning, traceID: traceID, spanID: spanID, parentSpanID: parentSpanID, fields: fields, audit: audit)
    }

    static func error(
        _ event: Event,
        category: Category,
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        fields: [Field] = [],
        audit: AuditKind? = nil
    ) {
        log(event, category: category, severity: .error, traceID: traceID, spanID: spanID, parentSpanID: parentSpanID, fields: fields, audit: audit)
    }

    static func log(
        _ event: Event,
        category: Category,
        severity: Severity,
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        fields: [Field] = [],
        audit: AuditKind? = nil
    ) {
        var payload: [String: Any] = [
            "schema_version": schemaVersion,
            "event": event.rawValue,
            "severity": severity.rawValue,
            "app_session_id": appSessionID,
            "process_id": Int(processID)
        ]

        if let traceID {
            payload["trace_id"] = traceID
        }

        if let spanID {
            payload["span_id"] = spanID
        }

        if let parentSpanID {
            payload["parent_span_id"] = parentSpanID
        }

        for field in fields {
            payload[field.key] = field.value
        }

        let message = jsonLine(payload)
        let logger = logger(category)

        switch severity {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }

        if let audit {
            AURAAuditLedger.shared.record(
                event: event.rawValue,
                category: category.rawValue,
                severity: severity.rawValue,
                auditKind: audit.rawValue,
                traceID: traceID,
                spanID: spanID,
                parentSpanID: parentSpanID,
                fields: fields.filter(\.includeInAudit)
            )
        }
    }

    static func makeTraceID(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    static func makeSpanID(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    static func durationMilliseconds(from startedAt: Date, to finishedAt: Date = Date()) -> Int {
        max(0, Int((finishedAt.timeIntervalSince(startedAt) * 1_000).rounded()))
    }

    static func byteCount(_ text: String) -> Int {
        text.lengthOfBytes(using: .utf8)
    }

    static func hermesOperation(arguments: [String]) -> String {
        guard let command = arguments.first else { return "unknown" }

        switch command {
        case "chat":
            return arguments.contains("--resume") ? "chat.resume" : "chat.start"
        case "mcp":
            return ["mcp", arguments.dropFirst().first].compactMap { $0 }.joined(separator: ".")
        case "sessions":
            return ["sessions", arguments.dropFirst().first].compactMap { $0 }.joined(separator: ".")
        default:
            return command
        }
    }

    static func hermesArgumentShape(arguments: [String]) -> String {
        guard !arguments.isEmpty else { return "[]" }

        var redacted: [String] = []
        var skipNext = false
        let valueFlags: Set<String> = ["-q", "--query", "--resume", "--command", "--env", "-t", "--tools", "--source"]

        for argument in arguments {
            if skipNext {
                redacted.append("<redacted>")
                skipNext = false
                continue
            }

            if valueFlags.contains(argument) {
                redacted.append(argument)
                skipNext = true
                continue
            }

            if argument.hasPrefix("--source=") {
                redacted.append("--source=<redacted>")
            } else {
                redacted.append(argument)
            }
        }

        return redacted.joined(separator: " ")
    }

    static func shellOperation(command: String) -> String {
        if command.contains("check_permissions") {
            return "cua.check_permissions"
        }

        if command.contains(" --version") {
            return "cua.version"
        }

        if command.contains(" status") {
            return "cua.status"
        }

        if command.contains(" serve") || command.contains("--args serve") {
            return "cua.daemon.start"
        }

        if command.contains("open -n") {
            return "mac.open"
        }

        return "shell"
    }

    private static func jsonLine(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"schema_version":1,"event":"telemetry_encoding_failed","severity":"error"}"#
        }

        return json
    }
}
