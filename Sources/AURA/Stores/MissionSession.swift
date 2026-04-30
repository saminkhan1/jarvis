import Darwin
import Foundation

/// One user request backed by one independently cancellable Hermes process.
@MainActor
final class MissionSession: ObservableObject, Identifiable {
    let id = UUID()
    let prompt: String
    let createdAt = Date()
    let context: ContextSnapshot?
    let traceID: String
    let missionID: String

    @Published private(set) var status: MissionStatus = .idle {
        didSet { onStateChanged?() }
    }
    @Published private(set) var output = "" {
        didSet { onStateChanged?() }
    }
    @Published private(set) var hermesSessionID: String? {
        didSet { onStateChanged?() }
    }
    @Published private(set) var startedAt: Date? {
        didSet { onStateChanged?() }
    }
    @Published private(set) var finishedAt: Date? {
        didSet { onStateChanged?() }
    }

    private(set) var outputChunkCount = 0
    var onStateChanged: (() -> Void)?

    private var process: Process?
    private let hermesService: HermesService

    init(
        prompt: String,
        context: ContextSnapshot?,
        hermesService: HermesService,
        traceID: String = AURATelemetry.makeTraceID(prefix: "mission"),
        missionID: String = AURATelemetry.makeSpanID(prefix: "mission")
    ) {
        self.prompt = prompt
        self.context = context
        self.hermesService = hermesService
        self.traceID = traceID
        self.missionID = missionID
    }

    var isFinished: Bool {
        switch status {
        case .completed, .failed, .cancelled:
            return true
        case .idle, .running:
            return false
        }
    }

    var displayTitle: String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled request" }
        return String(trimmed.prefix(36))
    }

    func start() {
        guard status == .idle else { return }

        let launchStartedAt = Date()
        startedAt = launchStartedAt
        status = .running
        output = "Starting Hermes...\n"

        AURATelemetry.info(
            .missionLaunchHermes,
            category: .mission,
            traceID: traceID,
            fields: [
                .string("mission_id", missionID),
                .string("operation", "invoke_agent"),
                .int("goal_chars", prompt.count)
            ],
            audit: .agent
        )

        do {
            process = try hermesService.start(
                arguments: AURAStore.hermesChatArguments(query: prompt, context: context),
                environment: Self.hermesEnvironment(missionID: missionID),
                traceID: traceID,
                onOutput: { [weak self] chunk in
                    Task { @MainActor in
                        self?.appendOutput(chunk)
                    }
                },
                onCompletion: { [weak self] result in
                    Task { @MainActor in
                        self?.finishMission(result, startedAt: launchStartedAt)
                    }
                }
            )
        } catch {
            AURATelemetry.error(
                .missionLaunchFailed,
                category: .mission,
                traceID: traceID,
                fields: [
                    .string("mission_id", missionID),
                    .string("error_type", String(describing: type(of: error))),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: launchStartedAt))
                ],
                audit: .mission
            )
            process = nil
            status = .failed
            output = error.localizedDescription
            finishedAt = Date()
        }
    }

    func cancel() {
        guard status == .running, let process else { return }

        process.terminate()
        let processIdentifier = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning {
                kill(processIdentifier, SIGKILL)
            }
        }

        self.process = nil
        status = .cancelled
        appendOutput("\nMission cancelled by user.")
        finishedAt = Date()

        AURATelemetry.info(
            .missionCancelledByUser,
            category: .mission,
            traceID: traceID,
            fields: [
                .string("mission_id", missionID),
                .int32("child_process_id", processIdentifier),
                .int("duration_ms", startedAt.map { AURATelemetry.durationMilliseconds(from: $0) } ?? 0)
            ],
            audit: .mission
        )
    }

    private func appendOutput(_ chunk: String) {
        guard !chunk.isEmpty else { return }

        outputChunkCount += 1
        AURATelemetry.debug(
            .missionOutputChunk,
            category: .mission,
            traceID: traceID,
            fields: [
                .string("mission_id", missionID),
                .int("chunk_index", outputChunkCount),
                .int("bytes", AURATelemetry.byteCount(chunk))
            ]
        )
        output += chunk
    }

    private func finishMission(_ result: Result<HermesCommandResult, Error>, startedAt: Date) {
        process = nil

        switch result {
        case .success(let commandResult):
            finishedAt = commandResult.finishedAt

            if status == .cancelled {
                AURATelemetry.info(
                    .missionFinishAfterCancel,
                    category: .mission,
                    traceID: commandResult.traceID,
                    fields: [
                        .string("mission_id", missionID),
                        .int32("exit_code", commandResult.exitCode),
                        .int("hermes_duration_ms", commandResult.durationMilliseconds)
                    ],
                    audit: .mission
                )
                return
            }

            let combinedOutput = commandResult.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdoutOutput = commandResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayOutput = commandResult.succeeded && !stdoutOutput.isEmpty ? stdoutOutput : combinedOutput

            hermesSessionID = AURASessionParsing.sessionID(in: combinedOutput)
            if let hermesSessionID {
                AURATelemetry.info(
                    .hermesSessionCaptured,
                    category: .hermes,
                    traceID: commandResult.traceID,
                    fields: [
                        .string("mission_id", missionID),
                        .string("hermes_session_id", hermesSessionID)
                    ],
                    audit: .agent
                )
            }

            output = displayOutput.isEmpty ? "Hermes returned no mission output." : displayOutput
            status = commandResult.succeeded ? .completed : .failed

            AURATelemetry.info(
                .missionFinish,
                category: .mission,
                traceID: commandResult.traceID,
                fields: [
                    .string("mission_id", missionID),
                    .string("status", status.title),
                    .int32("exit_code", commandResult.exitCode),
                    .int("mission_duration_ms", AURATelemetry.durationMilliseconds(from: startedAt, to: commandResult.finishedAt)),
                    .int("hermes_duration_ms", commandResult.durationMilliseconds),
                    .int("stdout_bytes", commandResult.outputByteCount),
                    .int("stderr_bytes", commandResult.errorByteCount),
                    .int("output_chunks", outputChunkCount)
                ],
                audit: .mission
            )

        case .failure(let error):
            finishedAt = Date()
            status = .failed
            output = error.localizedDescription

            AURATelemetry.error(
                .missionFinishFailed,
                category: .mission,
                traceID: traceID,
                fields: [
                    .string("mission_id", missionID),
                    .string("error_type", String(describing: type(of: error))),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ],
                audit: .mission
            )
        }
    }

    private static func hermesEnvironment(missionID: String) -> [String: String] {
        [
            "AURA_MISSION_ID": missionID
        ]
    }
}
