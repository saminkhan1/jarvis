import Foundation

enum CuaPermissionPane: String {
    case accessibility
    case screenRecording

    var title: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .screenRecording:
            return "Screen Recording"
        }
    }
}

struct CuaDriverStatus {
    var executablePath: String?
    var version: String?
    var daemonStatus: String
    var accessibilityGranted: Bool?
    var screenRecordingGranted: Bool?
    var isMCPRegistered: Bool
    var lastCheckedAt: Date?

    static let unknown = CuaDriverStatus(
        executablePath: nil,
        version: nil,
        daemonStatus: "Not checked",
        accessibilityGranted: nil,
        screenRecordingGranted: nil,
        isMCPRegistered: false,
        lastCheckedAt: nil
    )

    var isInstalled: Bool {
        executablePath != nil
    }

    static func isDaemonRunning(statusText: String) -> Bool {
        let normalized = statusText
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")

        let stoppedPhrases = [
            "not running",
            "not currently running",
            "isn't running",
            "stopped",
            "no daemon",
            "not installed"
        ]

        if stoppedPhrases.contains(where: { normalized.contains($0) }) {
            return false
        }

        return normalized.contains("daemon is running")
            || normalized.contains("is running")
            || normalized.contains("running")
    }

    var daemonRunning: Bool {
        Self.isDaemonRunning(statusText: daemonStatus)
    }

    var permissionsReady: Bool {
        accessibilityGranted == true && screenRecordingGranted == true
    }

    var hostSetupReady: Bool {
        isInstalled && daemonRunning && isMCPRegistered
    }

    var readyForHostControl: Bool {
        hostSetupReady && permissionsReady
    }

    var permissionIssues: [String] {
        guard isInstalled, daemonRunning else { return [] }

        var result: [String] = []

        switch accessibilityGranted {
        case .some(true):
            break
        case .some(false):
            result.append("Grant Accessibility permission to Cua Driver.")
        case .none:
            result.append("Check Accessibility permission.")
        }

        switch screenRecordingGranted {
        case .some(true):
            break
        case .some(false):
            result.append("Grant Screen Recording permission to Cua Driver.")
        case .none:
            result.append("Check Screen Recording permission.")
        }

        return result
    }

    var setupIssues: [String] {
        var result: [String] = []

        if !isInstalled {
            result.append("Install Cua Driver first.")
        }

        if isInstalled && !daemonRunning {
            result.append("Start CuaDriver daemon.")
        }

        if isInstalled && !isMCPRegistered {
            result.append("Register CUA daemon proxy with Hermes MCP.")
        }

        return result
    }

    var title: String {
        if readyForHostControl {
            return "Ready"
        }

        if !isInstalled {
            return "Not installed"
        }

        if !daemonRunning {
            return "Daemon needed"
        }

        if isInstalled && !permissionsReady {
            return "Permissions needed"
        }

        if !isMCPRegistered {
            return "MCP not registered"
        }

        return "Not ready"
    }

    var issues: [String] {
        var result: [String] = []

        result.append(contentsOf: permissionIssues)
        result.append(contentsOf: setupIssues.filter { !result.contains($0) })
        return result
    }
}
