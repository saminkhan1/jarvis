import AppKit
import Foundation

enum MissionStatus {
    case idle
    case needsApproval
    case running
    case completed
    case failed
    case cancelled

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .needsApproval:
            return "Needs approval"
        case .running:
            return "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

enum MissionInputMode: String, CaseIterable, Identifiable {
    case text
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text:
            return "Text"
        case .voice:
            return "Voice"
        }
    }

    var summary: String {
        switch self {
        case .text:
            return "The mission hotkey opens AURA's text composer."
        case .voice:
            return "The mission hotkey opens project-local Hermes Voice Mode and enables /voice on. Hermes owns microphone capture, STT, and TTS."
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            return "keyboard"
        case .voice:
            return "mic"
        }
    }

    var actionTitle: String {
        switch self {
        case .text:
            return "New Mission"
        case .voice:
            return "Start Listening"
        }
    }
}

struct ApprovalRequest: Identifiable {
    let id: UUID
    let reason: String
    let requestedAt: Date
    let risk: String
    let target: String?
    let scope: String
    let attachedWorkerID: String?

    init(
        id: UUID = UUID(),
        reason: String,
        requestedAt: Date,
        risk: String = "approval",
        target: String? = nil,
        scope: String = "one-time",
        attachedWorkerID: String? = nil
    ) {
        self.id = id
        self.reason = reason
        self.requestedAt = requestedAt
        self.risk = risk
        self.target = target
        self.scope = scope
        self.attachedWorkerID = attachedWorkerID
    }

    var title: String {
        reason.isEmpty ? "Hermes needs approval" : reason
    }
}

enum WorkerStatus: String {
    case queued
    case running
    case needsApproval
    case completed
    case failed
    case cancelled

    var title: String {
        switch self {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .needsApproval:
            return "Needs approval"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

enum WorkerDomain: String {
    case parent
    case delegation
    case tool
    case progress
    case approval
    case artifact

    var title: String {
        switch self {
        case .parent:
            return "Parent"
        case .delegation:
            return "Worker"
        case .tool:
            return "Tool"
        case .progress:
            return "Progress"
        case .approval:
            return "Approval"
        case .artifact:
            return "Artifact"
        }
    }

    var systemImage: String {
        switch self {
        case .parent:
            return "point.3.connected.trianglepath.dotted"
        case .delegation:
            return "person.2"
        case .tool:
            return "wrench.and.screwdriver"
        case .progress:
            return "arrow.triangle.2.circlepath"
        case .approval:
            return "hand.raised"
        case .artifact:
            return "doc"
        }
    }
}

struct WorkerRun: Identifiable {
    let id: String
    var title: String
    var status: WorkerStatus
    var domain: WorkerDomain
    var detail: String
    let startedAt: Date
    var updatedAt: Date
    var attachedApprovalID: UUID?
    var artifactIDs: [UUID]
}

enum AURAArtifactType: String {
    case file
    case folder
    case app
    case report
    case table
    case unknown

    var title: String {
        switch self {
        case .file:
            return "File"
        case .folder:
            return "Folder"
        case .app:
            return "App"
        case .report:
            return "Report"
        case .table:
            return "Table"
        case .unknown:
            return "Artifact"
        }
    }

    var systemImage: String {
        switch self {
        case .file:
            return "doc"
        case .folder:
            return "folder"
        case .app:
            return "app"
        case .report:
            return "doc.text"
        case .table:
            return "tablecells"
        case .unknown:
            return "shippingbox"
        }
    }
}

struct AURAArtifact: Identifiable {
    let id = UUID()
    let title: String
    let path: String
    let type: AURAArtifactType
    let owningWorkerID: String?
    let detectedAt: Date

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

struct ContextSnapshot {
    let capturedAt: Date
    let activeAppName: String
    let bundleIdentifier: String
    let processIdentifier: Int32?
    let cursorX: Double
    let cursorY: Double
    let projectRoot: String

    static func capture(projectRoot: URL = AURAPaths.projectRoot) -> ContextSnapshot {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let cursor = NSEvent.mouseLocation

        return ContextSnapshot(
            capturedAt: Date(),
            activeAppName: frontmostApp?.localizedName ?? "Unknown",
            bundleIdentifier: frontmostApp?.bundleIdentifier ?? "Unknown",
            processIdentifier: frontmostApp?.processIdentifier,
            cursorX: cursor.x,
            cursorY: cursor.y,
            projectRoot: projectRoot.path
        )
    }

    var markdownSummary: String {
        var lines = [
            "- Captured at: \(capturedAt.formatted(date: .numeric, time: .standard))",
            "- Active app: \(activeAppName)",
            "- Bundle ID: \(bundleIdentifier)",
            "- Cursor position: x=\(Int(cursorX)), y=\(Int(cursorY))",
            "- Project root: \(projectRoot)"
        ]

        if let processIdentifier {
            lines.insert("- PID: \(processIdentifier)", at: 3)
        }

        return lines.joined(separator: "\n")
    }
}
