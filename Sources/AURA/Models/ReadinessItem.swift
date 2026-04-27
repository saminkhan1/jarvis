import Foundation

enum ReadinessStatus: String {
    case ready
    case degraded
    case blocked
    case unknown

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .degraded:
            return "Degraded"
        case .blocked:
            return "Blocked"
        case .unknown:
            return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .degraded:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.octagon.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}

enum ReadinessGroup: String, CaseIterable, Identifiable {
    case runtime = "Runtime"
    case host = "Host"
    case local = "Local"
    case web = "Web"
    case apps = "Apps"
    case automation = "Automation"

    var id: String { rawValue }
}

struct ReadinessItem: Identifiable {
    let id: String
    let group: ReadinessGroup
    let title: String
    let status: ReadinessStatus
    let detail: String
    let command: String?
    let systemImage: String

    init(
        id: String,
        group: ReadinessGroup,
        title: String,
        status: ReadinessStatus,
        detail: String,
        command: String? = nil,
        systemImage: String
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.status = status
        self.detail = detail
        self.command = command
        self.systemImage = systemImage
    }
}
