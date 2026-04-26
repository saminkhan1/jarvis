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

struct ApprovalRequest: Identifiable {
    let id = UUID()
    let reason: String
    let requestedAt: Date

    var title: String {
        reason.isEmpty ? "Hermes needs approval" : reason
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
