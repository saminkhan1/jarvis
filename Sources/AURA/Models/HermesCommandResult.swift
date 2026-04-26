import Foundation

struct HermesCommandResult: Identifiable {
    let id = UUID()
    let command: String
    let arguments: [String]
    let output: String
    let errorOutput: String
    let exitCode: Int32
    let startedAt: Date
    let finishedAt: Date
    let traceID: String

    var succeeded: Bool {
        exitCode == 0
    }

    var durationMilliseconds: Int {
        AURATelemetry.durationMilliseconds(from: startedAt, to: finishedAt)
    }

    var outputByteCount: Int {
        AURATelemetry.byteCount(output)
    }

    var errorByteCount: Int {
        AURATelemetry.byteCount(errorOutput)
    }

    var combinedOutput: String {
        [output, errorOutput]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }
}
