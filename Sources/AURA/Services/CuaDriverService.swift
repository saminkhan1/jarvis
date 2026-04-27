import AppKit
import Darwin
import Foundation

final class CuaDriverService {
    private let appBundle = "/Applications/CuaDriver.app"
    private let appBinary = "/Applications/CuaDriver.app/Contents/MacOS/cua-driver"

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
        var isMCPRegistered = false

        if let preferredExecutablePath {
            let command = shellQuoted(preferredExecutablePath)
            async let versionResult = runShell("\(command) --version", traceID: traceID, telemetryEnabled: telemetryEnabled)
            async let daemonResult = runShell("\(command) status", traceID: traceID, telemetryEnabled: telemetryEnabled)
            async let mcpResult = testProjectHermesCuaMCP(traceID: traceID, telemetryEnabled: telemetryEnabled)

            let resolvedVersion = await versionResult
            let resolvedDaemon = await daemonResult

            version = resolvedVersion.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            daemonStatus = resolvedDaemon.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Unknown"

            if CuaDriverStatus.isDaemonRunning(statusText: daemonStatus) {
                let resolvedPermissions = await checkPermissions(for: preferredExecutablePath, prompt: false, traceID: traceID, telemetryEnabled: telemetryEnabled)
                accessibilityGranted = Self.permissionValue(named: "accessibility", in: resolvedPermissions.combinedOutput)
                screenRecordingGranted = Self.permissionValue(named: "screen recording", in: resolvedPermissions.combinedOutput)
            }
            isMCPRegistered = await mcpResult
        }

        let status = CuaDriverStatus(
            executablePath: preferredExecutablePath,
            version: version,
            daemonStatus: daemonStatus,
            accessibilityGranted: accessibilityGranted,
            screenRecordingGranted: screenRecordingGranted,
            isMCPRegistered: isMCPRegistered,
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
                    .bool("mcp_registered", status.isMCPRegistered),
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
            await progress("Cua Driver is not installed. Install it before host-control missions.")
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
            await progress("Cua Driver daemon is already running.")
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

        await progress("Starting Cua Driver daemon through CuaDriver.app...")
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
            await progress("Cua Driver is not installed. Install it before requesting macOS permissions.")
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

        if !currentStatus.daemonRunning {
            currentStatus = await startHostControlDaemon(traceID: traceID, progress: progress)
            guard currentStatus.daemonRunning else {
                await progress("Cua Driver daemon is not running. Start the daemon before requesting macOS permissions.")
                AURATelemetry.warning(
                    .cuaPermissionsRequestBlocked,
                    category: .cua,
                    traceID: traceID,
                    fields: [
                        .string("reason", "daemon_not_running"),
                        .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                    ],
                    audit: .governance
                )
                return currentStatus
            }
        }

        let didAttemptPermissionRequest = !currentStatus.permissionsReady

        if didAttemptPermissionRequest {
            await progress("Requesting Accessibility and Screen Recording permissions...")
            let requestResult = await requestPermissions(for: currentStatus, prompt: true, traceID: traceID)
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

        if didAttemptPermissionRequest || currentStatus.permissionsReady {
            await progress("Restarting CUA daemon so permission changes are picked up...")
            let restartResult = await restartDaemon(for: currentStatus, traceID: traceID)
            AURATelemetry.info(
                .cuaDaemonRestartCommandFinish,
                category: .cua,
                traceID: traceID,
                fields: [
                    .int32("exit_code", restartResult.exitCode),
                    .int("duration_ms", restartResult.durationMilliseconds)
                ],
                audit: .governance
            )
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            currentStatus = await status(traceID: traceID)
        }

        if currentStatus.permissionsReady && currentStatus.daemonRunning {
            await progress("CUA permissions are ready.")
        } else {
            await progress("CUA still needs: \(currentStatus.issues.joined(separator: " "))")
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

    func recommendedMCPCommandPath(for status: CuaDriverStatus) -> String? {
        if FileManager.default.isExecutableFile(atPath: appBinary) {
            return appBinary
        }

        return nil
    }

    func recommendedMCPProxyCommandPath() -> String? {
        let proxyPath = AURAPaths.projectRoot.appendingPathComponent("script/aura-cua-mcp").path
        if FileManager.default.isExecutableFile(atPath: proxyPath) {
            return proxyPath
        }

        return nil
    }

    private func startDaemon(for status: CuaDriverStatus, traceID: String) async -> ShellCommandResult {
        if FileManager.default.fileExists(atPath: appBundle) {
            return await runShell("open -n -g \(shellQuoted(appBundle)) --args serve", traceID: traceID)
        }

        guard let commandPath = recommendedMCPCommandPath(for: status) else {
            let now = Date()
            return ShellCommandResult(
                command: "start cua-driver daemon",
                output: "",
                errorOutput: "Cua Driver executable is missing.",
                exitCode: 1,
                startedAt: now,
                finishedAt: now,
                traceID: traceID
            )
        }

        return await runShell("\(shellQuoted(commandPath)) serve >/dev/null 2>&1 &", traceID: traceID)
    }

    private func restartDaemon(for status: CuaDriverStatus, traceID: String) async -> ShellCommandResult {
        return await startDaemon(for: status, traceID: traceID)
    }

    private func requestPermissions(for status: CuaDriverStatus, prompt: Bool, traceID: String) async -> ShellCommandResult {
        guard let commandPath = recommendedMCPCommandPath(for: status) else {
            let now = Date()
            return ShellCommandResult(
                command: "cua-driver call check_permissions",
                output: "",
                errorOutput: "Cua Driver executable is missing.",
                exitCode: 1,
                startedAt: now,
                finishedAt: now,
                traceID: traceID
            )
        }

        if prompt {
            return await launchPermissionPromptThroughApp(traceID: traceID)
        }

        return await checkPermissions(for: commandPath, prompt: prompt, traceID: traceID)
    }

    private func checkPermissions(
        for commandPath: String,
        prompt: Bool,
        traceID: String,
        telemetryEnabled: Bool = true
    ) async -> ShellCommandResult {
        let payload = prompt ? #"{"prompt":true}"# : #"{"prompt":false}"#
        return await runShell(
            "\(shellQuoted(commandPath)) call check_permissions \(shellQuoted(payload))",
            traceID: traceID,
            telemetryEnabled: telemetryEnabled
        )
    }

    private func launchPermissionPromptThroughApp(traceID: String) async -> ShellCommandResult {
        let payload = #"{"prompt":true}"#
        return await runShell("open -n \(shellQuoted(appBundle)) --args call check_permissions \(shellQuoted(payload))", traceID: traceID)
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
        return fileManager.isExecutableFile(atPath: appBinary) ? appBinary : nil
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func testProjectHermesCuaMCP(traceID: String, telemetryEnabled: Bool) async -> Bool {
        let wrapperPath = AURAPaths.projectRoot
            .appendingPathComponent("script/aura-hermes")
            .path
        guard FileManager.default.isExecutableFile(atPath: wrapperPath) else {
            return false
        }

        let result = await runShell(
            "\(shellQuoted(wrapperPath)) mcp test cua-driver",
            timeout: 20,
            traceID: traceID,
            telemetryEnabled: telemetryEnabled
        )
        let output = result.combinedOutput.lowercased()
        return result.succeeded
            && output.contains("connected")
            && output.contains("tools discovered")
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
