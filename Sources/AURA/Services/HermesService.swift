import Darwin
import Foundation

enum HermesServiceError: LocalizedError {
    case missingWrapper(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingWrapper(let path):
            return "Missing Hermes wrapper at \(path)"
        case .emptyOutput:
            return "Hermes returned no output."
        }
    }
}

final class HermesService {
    private let projectRoot: URL
    private let wrapperURL: URL

    init(projectRoot: URL = AURAPaths.projectRoot) {
        self.projectRoot = projectRoot
        self.wrapperURL = projectRoot.appendingPathComponent("script/aura-hermes")
    }

    func run(
        arguments: [String],
        environment: [String: String] = [:],
        traceID: String = AURATelemetry.makeTraceID(prefix: "hermes"),
        telemetryEnabled: Bool = true
    ) async throws -> HermesCommandResult {
        let operation = AURATelemetry.hermesOperation(arguments: arguments)

        guard FileManager.default.isExecutableFile(atPath: wrapperURL.path) else {
            if telemetryEnabled {
                AURATelemetry.error(
                    .hermesWrapperMissing,
                    category: .hermes,
                    traceID: traceID,
                    fields: [
                        .string("operation", operation),
                        .privateValue("path")
                    ],
                    audit: .agent
                )
            }
            throw HermesServiceError.missingWrapper(wrapperURL.path)
        }

        let cancellation = CancellableProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            let startedAt = Date()
            let outputBuffer = LockedData()
            let errorBuffer = LockedData()

            process.executableURL = wrapperURL
            process.arguments = arguments
            process.currentDirectoryURL = projectRoot
            process.standardOutput = standardOutput
            process.standardError = standardError
            process.environment = Self.mergedEnvironment(environment, traceID: traceID)
            cancellation.setProcess(process)

            guard !cancellation.isCancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }

            if telemetryEnabled {
                AURATelemetry.info(
                    .hermesCommandStart,
                    category: .hermes,
                    traceID: traceID,
                    fields: [
                        .string("operation", operation),
                        .string("args_shape", AURATelemetry.hermesArgumentShape(arguments: arguments), audit: false)
                    ],
                    audit: .agent
                )
            }

            standardOutput.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    outputBuffer.append(data)
                }
            }

            standardError.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    errorBuffer.append(data)
                }
            }

            process.terminationHandler = { terminatedProcess in
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil

                let remainingOutput = standardOutput.fileHandleForReading.availableData
                if !remainingOutput.isEmpty {
                    outputBuffer.append(remainingOutput)
                }

                let remainingError = standardError.fileHandleForReading.availableData
                if !remainingError.isEmpty {
                    errorBuffer.append(remainingError)
                }

                let result = HermesCommandResult(
                    command: self.wrapperURL.path,
                    arguments: arguments,
                    output: String(data: outputBuffer.data, encoding: .utf8) ?? "",
                    errorOutput: String(data: errorBuffer.data, encoding: .utf8) ?? "",
                    exitCode: terminatedProcess.terminationStatus,
                    startedAt: startedAt,
                    finishedAt: Date(),
                    traceID: traceID
                )

                if cancellation.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                if result.succeeded, telemetryEnabled {
                    AURATelemetry.info(
                        .hermesCommandFinish,
                        category: .hermes,
                        traceID: traceID,
                        fields: [
                            .string("operation", operation),
                            .int32("child_process_id", terminatedProcess.processIdentifier),
                            .int32("exit_code", result.exitCode),
                            .int("duration_ms", result.durationMilliseconds),
                            .int("stdout_bytes", result.outputByteCount),
                            .int("stderr_bytes", result.errorByteCount)
                        ],
                        audit: .agent
                    )
                } else if telemetryEnabled {
                    AURATelemetry.error(
                        .hermesCommandFinish,
                        category: .hermes,
                        traceID: traceID,
                        fields: [
                            .string("operation", operation),
                            .int32("child_process_id", terminatedProcess.processIdentifier),
                            .int32("exit_code", result.exitCode),
                            .int("duration_ms", result.durationMilliseconds),
                            .int("stdout_bytes", result.outputByteCount),
                            .int("stderr_bytes", result.errorByteCount)
                        ],
                        audit: .agent
                    )
                }

                continuation.resume(returning: result)
            }

            do {
                try process.run()
                if cancellation.isCancelled {
                    cancellation.cancel()
                }
            } catch {
                if telemetryEnabled {
                    AURATelemetry.error(
                        .hermesProcessLaunchError,
                        category: .hermes,
                        traceID: traceID,
                        fields: [
                            .string("operation", operation),
                            .string("error_type", String(describing: type(of: error)))
                        ],
                        audit: .agent
                    )
                }
                continuation.resume(throwing: error)
            }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func start(
        arguments: [String],
        environment: [String: String] = [:],
        traceID: String = AURATelemetry.makeTraceID(prefix: "hermes"),
        telemetryEnabled: Bool = true,
        onOutput: @escaping @Sendable (String) -> Void,
        onCompletion: @escaping @Sendable (Result<HermesCommandResult, Error>) -> Void
    ) throws -> Process {
        let operation = AURATelemetry.hermesOperation(arguments: arguments)

        guard FileManager.default.isExecutableFile(atPath: wrapperURL.path) else {
            if telemetryEnabled {
                AURATelemetry.error(
                    .hermesWrapperMissing,
                    category: .hermes,
                    traceID: traceID,
                    fields: [
                        .string("operation", operation),
                        .privateValue("path")
                    ],
                    audit: .agent
                )
            }
            throw HermesServiceError.missingWrapper(wrapperURL.path)
        }

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let startedAt = Date()
        let outputBuffer = LockedData()
        let errorBuffer = LockedData()

        process.executableURL = wrapperURL
        process.arguments = arguments
        process.currentDirectoryURL = projectRoot
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = Self.mergedEnvironment(environment, traceID: traceID)

        if telemetryEnabled {
            AURATelemetry.info(
                .hermesStreamStart,
                category: .hermes,
                traceID: traceID,
                fields: [
                    .string("operation", operation),
                    .string("args_shape", AURATelemetry.hermesArgumentShape(arguments: arguments), audit: false)
                ],
                audit: .agent
            )
        }

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputBuffer.append(data)
            onOutput(String(data: data, encoding: .utf8) ?? "")
        }

        standardError.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            errorBuffer.append(data)
            onOutput(String(data: data, encoding: .utf8) ?? "")
        }

        process.terminationHandler = { terminatedProcess in
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil

            let remainingOutput = standardOutput.fileHandleForReading.availableData
            if !remainingOutput.isEmpty {
                outputBuffer.append(remainingOutput)
            }

            let remainingError = standardError.fileHandleForReading.availableData
            if !remainingError.isEmpty {
                errorBuffer.append(remainingError)
            }

                let result = HermesCommandResult(
                    command: self.wrapperURL.path,
                    arguments: arguments,
                    output: String(data: outputBuffer.data, encoding: .utf8) ?? "",
                    errorOutput: String(data: errorBuffer.data, encoding: .utf8) ?? "",
                    exitCode: terminatedProcess.terminationStatus,
                    startedAt: startedAt,
                    finishedAt: Date(),
                    traceID: traceID
                )

                if result.succeeded, telemetryEnabled {
                    AURATelemetry.info(
                        .hermesStreamFinish,
                        category: .hermes,
                        traceID: traceID,
                        fields: [
                            .string("operation", operation),
                            .int32("child_process_id", terminatedProcess.processIdentifier),
                            .int32("exit_code", result.exitCode),
                            .int("duration_ms", result.durationMilliseconds),
                            .int("stdout_bytes", result.outputByteCount),
                            .int("stderr_bytes", result.errorByteCount)
                        ],
                        audit: .agent
                    )
                } else if telemetryEnabled {
                    AURATelemetry.error(
                        .hermesStreamFinish,
                        category: .hermes,
                        traceID: traceID,
                        fields: [
                            .string("operation", operation),
                            .int32("child_process_id", terminatedProcess.processIdentifier),
                            .int32("exit_code", result.exitCode),
                            .int("duration_ms", result.durationMilliseconds),
                            .int("stdout_bytes", result.outputByteCount),
                            .int("stderr_bytes", result.errorByteCount)
                        ],
                        audit: .agent
                    )
                }

                onCompletion(.success(result))
        }

        do {
            try process.run()
            return process
        } catch {
            if telemetryEnabled {
                AURATelemetry.error(
                    .hermesStreamLaunchError,
                    category: .hermes,
                    traceID: traceID,
                    fields: [
                        .string("operation", operation),
                        .string("error_type", String(describing: type(of: error)))
                    ],
                    audit: .agent
                )
            }
            onCompletion(.failure(error))
            throw error
        }
    }

    private static func mergedEnvironment(_ environment: [String: String], traceID: String) -> [String: String] {
        ProcessInfo.processInfo.environment
            .merging(environment) { _, new in new }
            .merging([
                "AURA_APP_SESSION_ID": AURATelemetry.appSessionID,
                "AURA_PARENT_PID": "\(AURATelemetry.processID)",
                "AURA_PROCESS_KIND": "hermes",
                "AURA_SKIP_WRAPPER_EXEC_TELEMETRY": "1",
                "AURA_TRACE_ID": traceID,
                "AURA_AUDIT_LEDGER_PATH": AURAAuditLedger.shared.ledgerURL.path
            ]) { _, new in new }
    }

    static func mergedEnvironmentForTesting(_ environment: [String: String], traceID: String) -> [String: String] {
        mergedEnvironment(environment, traceID: traceID)
    }
}

private final class LockedData {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}

private final class CancellableProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func setProcess(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancelled
        lock.unlock()

        if shouldTerminate {
            terminate(process)
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()

        if let process {
            terminate(process)
        }
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}
