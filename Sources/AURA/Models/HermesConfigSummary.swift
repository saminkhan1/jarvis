import Foundation

enum HermesConfigType: String, CaseIterable, Identifiable, Codable {
    case readOnly = "read_only"
    case askPerTask = "ask_per_task"
    case alwaysAllow = "always_allow"
    case custom
    case unavailable

    var id: String { rawValue }

    static var selectableCases: [HermesConfigType] {
        [.readOnly, .askPerTask, .alwaysAllow]
    }

    var title: String {
        switch self {
        case .readOnly:
            return "Read Only"
        case .askPerTask:
            return "Ask Per Task"
        case .alwaysAllow:
            return "Always Allow"
        case .custom:
            return "Custom"
        case .unavailable:
            return "Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .readOnly:
            return "eye"
        case .askPerTask:
            return "hand.raised"
        case .alwaysAllow:
            return "bolt"
        case .custom:
            return "slider.horizontal.3"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }

    var isSelectable: Bool {
        Self.selectableCases.contains(self)
    }
}

struct HermesConfigSummary: Codable {
    let configType: HermesConfigType
    let title: String
    let summary: String
    let approvalMode: String
    let cronMode: String
    let cliToolsets: [String]
    let cuaSurface: String
    let cuaTools: [String]
    let readCuaToolCount: Int
    let actionCuaToolCount: Int
    let configPath: String
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case configType = "config_type"
        case title
        case summary
        case approvalMode = "approval_mode"
        case cronMode = "cron_mode"
        case cliToolsets = "cli_toolsets"
        case cuaSurface = "cua_surface"
        case cuaTools = "cua_tools"
        case readCuaToolCount = "read_cua_tool_count"
        case actionCuaToolCount = "action_cua_tool_count"
        case configPath = "config_path"
        case warnings
    }

    static let unavailable = HermesConfigSummary(
        configType: .unavailable,
        title: "Unavailable",
        summary: "Hermes config has not been checked yet.",
        approvalMode: "unknown",
        cronMode: "unknown",
        cliToolsets: [],
        cuaSurface: "unknown",
        cuaTools: [],
        readCuaToolCount: 0,
        actionCuaToolCount: 0,
        configPath: AURAPaths.hermesHome.appendingPathComponent("config.yaml").path,
        warnings: []
    )

    var cuaSurfaceTitle: String {
        switch cuaSurface {
        case "read_only":
            return "CUA read only"
        case "action_enabled":
            return "CUA actions"
        case "all":
            return "CUA all tools"
        case "custom":
            return "CUA custom"
        case "unconfigured":
            return "CUA unconfigured"
        default:
            return cuaSurface.replacingOccurrences(of: "_", with: " ")
        }
    }

    var detailLine: String {
        "\(approvalMode) approvals · \(cliToolsets.count) CLI toolsets · \(readCuaToolCount) read / \(actionCuaToolCount) action CUA tools"
    }
}
