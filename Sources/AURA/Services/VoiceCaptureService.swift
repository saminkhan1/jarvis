import AVFoundation
import Foundation

enum VoiceCaptureServiceError: LocalizedError {
    case microphoneDenied
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is not available for AURA."
        case .couldNotStart:
            return "Could not start microphone recording."
        }
    }
}

final class VoiceCaptureService: NSObject {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var startedAt: Date?

    var elapsedSeconds: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    func microphonePermissionStatus() -> MicrophonePermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    func requestMicrophoneAccess() async -> MicrophonePermissionStatus {
        let status = microphonePermissionStatus()
        switch status {
        case .granted, .denied, .restricted, .unknown:
            return status
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            }
        }
    }

    func startRecording() throws -> URL {
        _ = stopRecording()
        try FileManager.default.createDirectory(
            at: Self.recordingDirectory,
            withIntermediateDirectories: true
        )

        let url = Self.recordingDirectory
            .appendingPathComponent("aura-voice-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw VoiceCaptureServiceError.couldNotStart
        }

        self.recorder = recorder
        self.recordingURL = url
        self.startedAt = Date()
        return url
    }

    func stopRecording() -> URL? {
        guard let recorder else { return nil }
        let url = recordingURL
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        self.startedAt = nil
        return url
    }

    func cancelRecording() {
        let url = recordingURL
        recorder?.stop()
        recorder = nil
        recordingURL = nil
        startedAt = nil

        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func normalizedInputLevel() -> Double {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        guard power.isFinite else { return 0 }
        let clamped = max(-60, min(0, Double(power)))
        return pow(10, clamped / 40)
    }

    private static var recordingDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("aura-voice", isDirectory: true)
    }
}

extension VoiceCaptureService: AVAudioRecorderDelegate {}
