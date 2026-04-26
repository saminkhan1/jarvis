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

enum GlobalAutomationPolicy: String, CaseIterable, Identifiable {
    case readOnly
    case writePerTask
    case writeAlways

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readOnly:
            return "Read Only"
        case .writePerTask:
            return "Ask Per Task"
        case .writeAlways:
            return "Always Allow"
        }
    }

    var summary: String {
        switch self {
        case .readOnly:
            return "Hermes can read context, inspect the screen, explain, research, and plan. No writes or host-control actions."
        case .writePerTask:
            return "Hermes can inspect the screen and stops with NEEDS_APPROVAL before local writes or host-control actions."
        case .writeAlways:
            return "Hermes may perform non-destructive local writes and CUA host-control actions without asking each task."
        }
    }

    var systemImage: String {
        switch self {
        case .readOnly:
            return "eye"
        case .writePerTask:
            return "hand.raised"
        case .writeAlways:
            return "bolt.badge.checkmark"
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
