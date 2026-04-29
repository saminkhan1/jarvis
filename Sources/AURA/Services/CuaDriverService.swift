import ApplicationServices
import AppKit
import CoreGraphics
import Darwin
import Foundation

final class CuaDriverService {
    private let helperName = "cua-driver"
    private let externalAppBinary = "/Applications/CuaDriver.app/Contents/MacOS/cua-driver"

    func status(
        traceID: String = AURATelemetry.makeTraceID(prefix: "cua-status"),
        telemetryEnabled: Bool = true
    ) async -> CuaDriverStatus {
        let startedAt = Date()
        if telemetryEnabled {
            AURATelemetry.info(.cuaStatusStart, category: .cua, traceID: traceID)
        }

        let preferredExecutablePath = preferredExecutablePath()

        var version: String?
        var daemonStatus = "Not installed"
        var accessibilityGranted: Bool?
        var screenRecordingGranted: Bool?
        var isHermesComputerUseEnabled = false
        var isHermesComputerUseSmokePassed = false

        if let preferredExecutablePath {
            let command = shellQuoted(preferredExecutablePath)
            async let versionResult = runShell("\(command) --version", traceID: traceID, telemetryEnabled: telemetryEnabled)
            async let hermesToolResult = testProjectHermesComputerUse(traceID: traceID, telemetryEnabled: telemetryEnabled)

            let resolvedVersion = await versionResult

            version = resolvedVersion.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            daemonStatus = localDaemonStatus()
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
            isHermesComputerUseEnabled = await hermesToolResult
            if accessibilityGranted == true,
               screenRecordingGranted == true,
               isHermesComputerUseEnabled {
                isHermesComputerUseSmokePassed = await smokeTestHermesComputerUse(traceID: traceID, telemetryEnabled: telemetryEnabled)
            }
        }

        let status = CuaDriverStatus(
            executablePath: preferredExecutablePath,
            version: version,
            daemonStatus: daemonStatus,
            accessibilityGranted: accessibilityGranted,
            screenRecordingGranted: screenRecordingGranted,
            isHermesComputerUseEnabled: isHermesComputerUseEnabled,
            isHermesComputerUseSmokePassed: isHermesComputerUseSmokePassed,
            lastCheckedAt: Date()
        )

        if telemetryEnabled {
            AURATelemetry.info(
                .cuaStatusFinish,
                category: .cua,
                traceID: traceID,
                fields: [
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt)),
                    .bool("installed", status.isInstalled),
                    .bool("daemon_running", status.daemonRunning),
                    .bool("permissions_ready", status.permissionsReady),
                    .bool("computer_use_enabled", status.isHermesComputerUseEnabled),
                    .bool("computer_use_smoke_passed", status.isHermesComputerUseSmokePassed),
                    .int("issue_count", status.issues.count)
                ]
            )
        }

        return status
    }

    func prepareHostControl(
        traceID: String = AURATelemetry.makeTraceID(prefix: "cua-prepare"),
        telemetryEnabled: Bool = true,
        progress: @escaping (String) async -> Void
    ) async -> CuaDriverStatus {
        if telemetryEnabled {
            AURATelemetry.info(.cuaPrepareStart, category: .cua, traceID: traceID)
        }
        await progress("Checking CUA Driver without requesting permissions...")
        let result = await status(traceID: traceID, telemetryEnabled: telemetryEnabled)
        if telemetryEnabled {
            AURATelemetry.info(
                .cuaPrepareFinish,
                category: .cua,
                traceID: traceID,
                fields: [.bool("ready", result.readyForHostControl)]
            )
        }
        return result
    }

    func startHostControlDaemon(
        traceID: String = AURATelemetry.makeTraceID(prefix: "cua-daemon"),
        progress: @escaping (String) async -> Void
    ) async -> CuaDriverStatus {
        let startedAt = Date()
        AURATelemetry.info(.cuaDaemonStartRequested, category: .cua, traceID: traceID, audit: .governance)
        var currentStatus = await status(traceID: traceID)

        guard currentStatus.isInstalled else {
            await progress("AURA host-control support is not installed. Run setup before host-control missions.")
            AURATelemetry.warning(
                .cuaDaemonStartBlocked,
                category: .cua,
                traceID: traceID,
                fields: [
                    .string("reason", "not_installed"),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ],
                audit: .governance
            )
            return currentStatus
        }

        guard !currentStatus.daemonRunning else {
            await progress("AURA host-control helper is already running.")
            AURATelemetry.info(
                .cuaDaemonStartSkipped,
                category: .cua,
                traceID: traceID,
                fields: [
                    .string("reason", "already_running"),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ],
                audit: .governance
            )
            return currentStatus
        }

        await progress("Starting AURA host-control helper...")
        let startResult = await startDaemon(for: currentStatus, traceID: traceID)
        AURATelemetry.info(
            .cuaDaemonStartCommandFinish,
            category: .cua,
            traceID: traceID,
            fields: [
                .int32("exit_code", startResult.exitCode),
                .int("duration_ms", startResult.durationMilliseconds)
            ],
            audit: .governance
        )
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        currentStatus = await status(traceID: traceID)
        AURATelemetry.info(
            .cuaDaemonStartFinish,
            category: .cua,
            traceID: traceID,
            fields: [
                .bool("daemon_running", currentStatus.daemonRunning),
                .bool("ready", currentStatus.readyForHostControl),
                .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
            ],
            audit: .governance
        )
        return currentStatus
    }

    func requestHostControlPermissions(
        traceID: String = AURATelemetry.makeTraceID(prefix: "cua-permissions"),
        focusing pane: CuaPermissionPane? = nil,
        progress: @escaping (String) async -> Void
    ) async -> CuaDriverStatus {
        let startedAt = Date()
        AURATelemetry.info(
            .cuaPermissionsRequestStart,
            category: .cua,
            traceID: traceID,
            fields: [.string("focus_pane", pane?.rawValue ?? "auto")],
            audit: .governance
        )
        var currentStatus = await status(traceID: traceID)

        guard currentStatus.isInstalled else {
            await progress("AURA host-control support is not installed. Run setup before requesting macOS permissions.")
            AURATelemetry.warning(
                .cuaPermissionsRequestBlocked,
                category: .cua,
                traceID: traceID,
                fields: [
                    .string("reason", "not_installed"),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ],
                audit: .governance
            )
            return currentStatus
        }

        let didAttemptPermissionRequest = !currentStatus.permissionsReady

        if didAttemptPermissionRequest {
            await progress("Requesting AURA Accessibility and Screen Recording permissions...")
            let requestResult = await requestPermissions(for: currentStatus, prompt: true, focusing: pane, traceID: traceID)
            AURATelemetry.info(
                .cuaPermissionsPromptCommandFinish,
                category: .cua,
                traceID: traceID,
                fields: [
                    .int32("exit_code", requestResult.exitCode),
                    .int("duration_ms", requestResult.durationMilliseconds)
                ],
                audit: .governance
            )
            currentStatus = await status(traceID: traceID)

            let statusForSettings = currentStatus
            await MainActor.run {
                openPrivacySettings(for: statusForSettings, focusing: pane)
            }

            if !currentStatus.permissionsReady {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                currentStatus = await status(traceID: traceID)
            }
        }

        if currentStatus.permissionsReady {
            await progress("AURA host-control permissions are ready.")
        } else {
            await progress("AURA still needs: \(currentStatus.issues.joined(separator: " "))")
        }

        AURATelemetry.info(
            .cuaPermissionsRequestFinish,
            category: .cua,
            traceID: traceID,
            fields: [
                .bool("ready", currentStatus.readyForHostControl),
                .bool("permissions_ready", currentStatus.permissionsReady),
                .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
            ],
            audit: .governance
        )
        return currentStatus
    }

    func recommendedCuaDriverCommandPath(for status: CuaDriverStatus) -> String? {
        if let preferredExecutablePath = preferredExecutablePath() {
            return preferredExecutablePath
        }

        return nil
    }

    private func startDaemon(for status: CuaDriverStatus, traceID: String) async -> ShellCommandResult {
        guard let commandPath = recommendedCuaDriverCommandPath(for: status) else {
            let now = Date()
            return ShellCommandResult(
                command: "start AURA host-control helper",
                output: "",
                errorOutput: "AURA host-control helper is missing.",
                exitCode: 1,
                startedAt: now,
                finishedAt: now,
                traceID: traceID
            )
        }

        return await launchDaemonProcess(commandPath: commandPath, traceID: traceID)
    }

    private func restartDaemon(for status: CuaDriverStatus, traceID: String) async -> ShellCommandResult {
        if let commandPath = recommendedCuaDriverCommandPath(for: status) {
            _ = await runShell("\(shellQuoted(commandPath)) stop", traceID: traceID)
        }
        return await startDaemon(for: status, traceID: traceID)
    }

    private func launchDaemonProcess(commandPath: String, traceID: String) async -> ShellCommandResult {
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: commandPath)
        process.arguments = ["serve"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "AURA_APP_SESSION_ID": AURATelemetry.appSessionID,
            "AURA_PARENT_PID": "\(AURATelemetry.processID)",
            "AURA_PROCESS_KIND": "cua-helper",
            "AURA_TRACE_ID": traceID,
            "AURA_AUDIT_LEDGER_PATH": AURAAuditLedger.shared.ledgerURL.path
        ]) { _, new in new }

        let nullOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullOutput
        process.standardError = nullOutput

        do {
            try process.run()
            try? await Task.sleep(nanoseconds: 250_000_000)

            let exitCode: Int32
            let errorOutput: String
            if process.isRunning {
                exitCode = 0
                errorOutput = ""
            } else {
                process.waitUntilExit()
                exitCode = process.terminationStatus
                errorOutput = "AURA host-control helper exited immediately."
            }

            return ShellCommandResult(
                command: "\(commandPath) serve",
                output: "",
                errorOutput: errorOutput,
                exitCode: exitCode,
                startedAt: startedAt,
                finishedAt: Date(),
                traceID: traceID
            )
        } catch {
            return ShellCommandResult(
                command: "\(commandPath) serve",
                output: "",
                errorOutput: error.localizedDescription,
                exitCode: 1,
                startedAt: startedAt,
                finishedAt: Date(),
                traceID: traceID
            )
        }
    }

    private func requestPermissions(
        for status: CuaDriverStatus,
        prompt: Bool,
        focusing pane: CuaPermissionPane?,
        traceID: String
    ) async -> ShellCommandResult {
        guard let commandPath = recommendedCuaDriverCommandPath(for: status) else {
            let now = Date()
            return ShellCommandResult(
                command: "AURA host-control helper call check_permissions",
                output: "",
                errorOutput: "AURA host-control helper is missing.",
                exitCode: 1,
                startedAt: now,
                finishedAt: now,
                traceID: traceID
            )
        }

        if prompt {
            await MainActor.run {
                requestAuraHostControlPermissions(focusing: pane)
            }
            return auraPermissionResult(command: "AURA privacy prompt", traceID: traceID)
        }

        return await checkPermissions(for: commandPath, prompt: prompt, traceID: traceID)
    }

    private func checkPermissions(
        for commandPath: String,
        prompt: Bool,
        traceID: String,
        telemetryEnabled: Bool = true
    ) async -> ShellCommandResult {
        if prompt {
            await MainActor.run {
                requestAuraHostControlPermissions(focusing: nil)
            }
        }

        return auraPermissionResult(command: "AURA privacy preflight", traceID: traceID)
    }

    private func auraPermissionResult(command: String, traceID: String) -> ShellCommandResult {
        let now = Date()
        let accessibility = AXIsProcessTrusted() ? "granted" : "not granted"
        let screenRecording = CGPreflightScreenCaptureAccess() ? "granted" : "not granted"
        return ShellCommandResult(
            command: command,
            output: "Accessibility: \(accessibility)\nScreen Recording: \(screenRecording)\n",
            errorOutput: "",
            exitCode: accessibility == "granted" && screenRecording == "granted" ? 0 : 1,
            startedAt: now,
            finishedAt: now,
            traceID: traceID
        )
    }

    @MainActor
    func openPrivacySettings(_ pane: CuaPermissionPane) {
        AURATelemetry.info(
            .macPrivacySettingsOpen,
            category: .cua,
            fields: [.string("pane", pane.rawValue)],
            audit: .governance
        )
        switch pane {
        case .accessibility:
            openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    @MainActor
    private func openPrivacySettings(for status: CuaDriverStatus, focusing pane: CuaPermissionPane?) {
        if let pane {
            openPrivacySettings(pane)
            return
        }

        if status.accessibilityGranted != true {
            openPrivacySettings(.accessibility)
            return
        }

        if status.screenRecordingGranted != true {
            openPrivacySettings(.screenRecording)
        }
    }

    @MainActor
    private func openSystemSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func requestAuraHostControlPermissions(focusing pane: CuaPermissionPane?) {
        switch pane {
        case .accessibility:
            requestAuraAccessibilityPermission()
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .none:
            requestAuraAccessibilityPermission()
            _ = CGRequestScreenCaptureAccess()
        }
    }

    private func requestAuraAccessibilityPermission() {
        let promptOption = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let accessibilityOptions = [promptOption: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(accessibilityOptions)
    }

    private func runShell(
        _ command: String,
        timeout: TimeInterval = 8,
        traceID: String = AURATelemetry.makeTraceID(prefix: "shell"),
        telemetryEnabled: Bool = true
    ) async -> ShellCommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            let timeoutState = ShellTimeoutState()
            let startedAt = Date()
            let operation = AURATelemetry.shellOperation(command: command)

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.standardOutput = output
            process.standardError = error
            process.environment = ProcessInfo.processInfo.environment.merging([
                "AURA_APP_SESSION_ID": AURATelemetry.appSessionID,
                "AURA_PARENT_PID": "\(AURATelemetry.processID)",
                "AURA_PROCESS_KIND": "cua-shell",
                "AURA_TRACE_ID": traceID,
                "AURA_AUDIT_LEDGER_PATH": AURAAuditLedger.shared.ledgerURL.path
            ]) { _, new in new }

            if telemetryEnabled {
                AURATelemetry.info(
                    .shellCommandStart,
                    category: .process,
                    traceID: traceID,
                    fields: [
                        .string("operation", operation),
                        .int("timeout_seconds", Int(timeout))
                    ]
                )
            }

            process.terminationHandler = { terminatedProcess in
                let outputData = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = error.fileHandleForReading.readDataToEndOfFile()
                let finishedAt = Date()
                let timeoutMessage = "Timed out after \(Int(timeout)) seconds."
                let didTimeOut = timeoutState.didTimeOut
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                let finalErrorOutput = didTimeOut
                    ? [errorOutput, timeoutMessage]
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .joined(separator: "\n")
                    : errorOutput

                let result = ShellCommandResult(
                    command: command,
                    output: String(data: outputData, encoding: .utf8) ?? "",
                    errorOutput: finalErrorOutput,
                    exitCode: didTimeOut ? 124 : terminatedProcess.terminationStatus,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    traceID: traceID
                )

                if didTimeOut, telemetryEnabled {
                    AURATelemetry.error(
                        .shellCommandTimeout,
                        category: .process,
                        traceID: traceID,
                        fields: [
                            .string("operation", operation),
                            .int("duration_ms", result.durationMilliseconds)
                        ]
                    )
                }

                if result.succeeded, telemetryEnabled {
                    AURATelemetry.info(
                        .shellCommandFinish,
                        category: .process,
                        traceID: traceID,
                        fields: [
                            .string("operation", operation),
                            .int32("child_process_id", terminatedProcess.processIdentifier),
                            .int32("exit_code", result.exitCode),
                            .int("duration_ms", result.durationMilliseconds),
                            .int("stdout_bytes", result.outputByteCount),
                            .int("stderr_bytes", result.errorByteCount)
                        ]
                    )
                } else if telemetryEnabled {
                    AURATelemetry.error(
                        .shellCommandFinish,
                        category: .process,
                        traceID: traceID,
                        fields: [
                            .string("operation", operation),
                            .int32("child_process_id", terminatedProcess.processIdentifier),
                            .int32("exit_code", result.exitCode),
                            .int("duration_ms", result.durationMilliseconds),
                            .int("stdout_bytes", result.outputByteCount),
                            .int("stderr_bytes", result.errorByteCount)
                        ]
                    )
                }

                continuation.resume(returning: result)
            }

            do {
                try process.run()
                let workItem = DispatchWorkItem {
                    guard process.isRunning else { return }

                    timeoutState.markTimedOut()
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)
            } catch {
                let finishedAt = Date()
                if telemetryEnabled {
                    AURATelemetry.error(
                        .shellProcessLaunchError,
                        category: .process,
                        traceID: traceID,
                        fields: [
                            .string("operation", operation),
                            .string("error_type", String(describing: type(of: error)))
                        ]
                    )
                }
                continuation.resume(returning: ShellCommandResult(
                    command: command,
                    output: "",
                    errorOutput: error.localizedDescription,
                    exitCode: 1,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    traceID: traceID
                ))
            }
        }
    }

    private func preferredExecutablePath() -> String? {
        let fileManager = FileManager.default

        if let environmentPath = ProcessInfo.processInfo.environment["HERMES_CUA_DRIVER_CMD"],
           fileManager.isExecutableFile(atPath: environmentPath) {
            return environmentPath
        }

        if let bundledPath = bundledHelperPath(),
           fileManager.isExecutableFile(atPath: bundledPath) {
            return bundledPath
        }

        return fileManager.isExecutableFile(atPath: externalAppBinary) ? externalAppBinary : nil
    }

    private func bundledHelperPath() -> String? {
        guard let executableURL = Bundle.main.executableURL else { return nil }
        return executableURL
            .deletingLastPathComponent()
            .appendingPathComponent(helperName)
            .path
    }

    private func localDaemonStatus() -> String {
        let cacheURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/cua-driver")
        let pidURL = cacheURL.appendingPathComponent("cua-driver.pid")
        let socketURL = cacheURL.appendingPathComponent("cua-driver.sock")

        guard FileManager.default.fileExists(atPath: socketURL.path),
              let pidText = try? String(contentsOf: pidURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = pid_t(pidText),
              kill(pid, 0) == 0 else {
            return "AURA host-control helper is not running"
        }

        return "AURA host-control helper is running"
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static let hermesComputerUseSmokePrompt = """
    This is a read-only AURA host-control startup smoke test.
    Use the computer_use tool exactly twice:
    1. action=list_apps
    2. action=capture, mode=ax, app=AURA
    Do not click or type. Do not use any other tool.
    Reply exactly OK if both tool calls succeeded. Otherwise reply FAIL plus the exact error.
    """

    private func testProjectHermesComputerUse(traceID: String, telemetryEnabled: Bool) async -> Bool {
        let wrapperPath = AURAPaths.projectRoot
            .appendingPathComponent("script/aura-hermes")
            .path
        guard FileManager.default.isExecutableFile(atPath: wrapperPath) else {
            return false
        }

        let result = await runShell(
            "\(shellQuoted(wrapperPath)) tools list --platform cli",
            timeout: 20,
            traceID: traceID,
            telemetryEnabled: telemetryEnabled
        )
        let output = result.combinedOutput.lowercased()
        return result.succeeded && Self.hermesComputerUseEnabled(in: output)
    }

    private func smokeTestHermesComputerUse(traceID: String, telemetryEnabled: Bool) async -> Bool {
        let wrapperPath = AURAPaths.projectRoot
            .appendingPathComponent("script/aura-hermes")
            .path
        guard FileManager.default.isExecutableFile(atPath: wrapperPath) else {
            return false
        }

        let result = await runShell(
            "\(shellQuoted(wrapperPath)) chat -Q --yolo --source aura-cua-preflight --toolsets computer_use --max-turns 10 -q \(shellQuoted(Self.hermesComputerUseSmokePrompt))",
            timeout: 45,
            traceID: traceID,
            telemetryEnabled: telemetryEnabled
        )
        let normalized = result.combinedOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return result.succeeded
            && normalized.contains("ok")
            && !normalized.contains("fail")
            && !normalized.contains("unknown tool")
            && !normalized.contains("error")
    }

    static func hermesComputerUseEnabled(in toolsListOutput: String) -> Bool {
        toolsListOutput
            .lowercased()
            .components(separatedBy: .newlines)
            .contains { line in
                let fields = line.split { $0 == " " || $0 == "\t" }.map(String.init)
                guard let computerUseIndex = fields.firstIndex(of: "computer_use"), computerUseIndex > 0 else {
                    return false
                }
                return fields[..<computerUseIndex].contains("enabled")
                    && !fields[..<computerUseIndex].contains("disabled")
            }
    }

    private static func permissionValue(named name: String, in output: String) -> Bool? {
        let normalized = output
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        guard normalized.contains(name) else { return nil }

        for rawLine in normalized.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.contains(name) else { continue }

            if line.contains("not granted")
                || line.contains("denied")
                || line.contains("false")
                || line.contains("❌") {
                return false
            }

            if line.contains("granted")
                || line.contains("allowed")
                || line.contains("true")
                || line.contains("✅") {
                return true
            }
        }

        return nil
    }
}

private final class ShellTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
