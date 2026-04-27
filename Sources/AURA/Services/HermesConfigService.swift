import Foundation

enum HermesConfigServiceError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

final class HermesConfigService {
    private let hermesService: HermesService
    private let configURL: URL

    private static let readCuaTools = [
        "check_permissions",
        "get_accessibility_tree",
        "get_agent_cursor_state",
        "get_config",
        "get_cursor_position",
        "get_recording_state",
        "get_screen_size",
        "get_window_state",
        "list_apps",
        "list_windows",
        "screenshot",
        "zoom",
    ]

    private static let actionCuaTools = [
        "click",
        "double_click",
        "hotkey",
        "launch_app",
        "move_cursor",
        "press_key",
        "replay_trajectory",
        "right_click",
        "scroll",
        "set_agent_cursor_enabled",
        "set_agent_cursor_motion",
        "set_config",
        "set_recording",
        "set_value",
        "type_text",
        "type_text_chars",
    ]

    private static let readOnlyToolsets = [
        "web",
        "skills",
        "todo",
        "memory",
        "session_search",
        "clarify",
        "delegation",
    ]

    private static let localAgentToolsets = [
        "web",
        "browser",
        "terminal",
        "file",
        "code_execution",
        "skills",
        "todo",
        "memory",
        "session_search",
        "clarify",
        "delegation",
        "cronjob",
        "tts",
    ]

    private static let configurableToolsets = [
        "web",
        "browser",
        "terminal",
        "file",
        "code_execution",
        "vision",
        "image_gen",
        "moa",
        "tts",
        "skills",
        "todo",
        "memory",
        "session_search",
        "clarify",
        "delegation",
        "cronjob",
        "messaging",
        "rl",
        "homeassistant",
        "spotify",
    ]

    init(hermesService: HermesService = HermesService(), configURL: URL = AURAPaths.hermesHome.appendingPathComponent("config.yaml")) {
        self.hermesService = hermesService
        self.configURL = configURL
    }

    func status() async throws -> HermesConfigSummary {
        let toolsOutput = try await checkedHermesOutput(["tools", "list", "--platform", "cli"])
        let enabledToolsets = Self.parseEnabledToolsets(from: toolsOutput)
        let cuaTools = Self.parseCuaTools(from: toolsOutput)
        let approvalMode = Self.readApprovalMode(from: configURL)
        let cronMode = Self.readCronMode(from: configURL)
        let configType = Self.deriveConfigType(
            enabledToolsets: enabledToolsets,
            cuaTools: cuaTools,
            approvalMode: approvalMode
        )

        return Self.summary(
            configType: configType,
            enabledToolsets: enabledToolsets,
            cuaTools: cuaTools,
            approvalMode: approvalMode,
            cronMode: cronMode,
            configPath: configURL.path
        )
    }

    func apply(_ configType: HermesConfigType) async throws -> HermesConfigSummary {
        guard configType.isSelectable else {
            throw HermesConfigServiceError.commandFailed("Only standard Hermes config types can be applied.")
        }

        let enabledToolsets = Self.toolsets(for: configType)
        let disabledToolsets = Self.configurableToolsets.filter { !enabledToolsets.contains($0) }
        let readMCPTools = Self.readCuaTools.map { "cua-driver:\($0)" }
        let actionMCPTools = Self.actionCuaTools.map { "cua-driver:\($0)" }

        try await runHermes(["tools", "enable", "--platform", "cli"] + enabledToolsets)
        try await runHermes(["tools", "disable", "--platform", "cli"] + disabledToolsets)

        switch configType {
        case .readOnly:
            try await runHermes(["tools", "enable", "--platform", "cli"] + readMCPTools)
            try await runHermes(["tools", "disable", "--platform", "cli"] + actionMCPTools)
            try await runHermes(["config", "set", "approvals.mode", "manual"])
        case .askPerTask:
            try await runHermes(["tools", "enable", "--platform", "cli"] + readMCPTools + actionMCPTools)
            try await runHermes(["config", "set", "approvals.mode", "manual"])
        case .alwaysAllow:
            try await runHermes(["tools", "enable", "--platform", "cli"] + readMCPTools + actionMCPTools)
            try await runHermes(["config", "set", "approvals.mode", "off"])
        case .custom, .unavailable:
            break
        }

        try await runHermes(["config", "set", "approvals.cron_mode", "deny"])
        try await runHermes(["config", "set", "aura.config_type", configType.rawValue])

        return try await status()
    }

    private func runHermes(_ arguments: [String]) async throws {
        let result = try await hermesService.run(arguments: arguments, telemetryEnabled: false)
        guard result.succeeded else {
            throw HermesConfigServiceError.commandFailed(result.combinedOutput)
        }
    }

    private func checkedHermesOutput(_ arguments: [String]) async throws -> String {
        let result = try await hermesService.run(arguments: arguments, telemetryEnabled: false)
        guard result.succeeded else {
            throw HermesConfigServiceError.commandFailed(result.combinedOutput)
        }
        return result.combinedOutput
    }

    private static func toolsets(for configType: HermesConfigType) -> [String] {
        switch configType {
        case .readOnly:
            return readOnlyToolsets
        case .askPerTask, .alwaysAllow:
            return localAgentToolsets
        case .custom, .unavailable:
            return []
        }
    }

    private static func parseEnabledToolsets(from output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let text = String(line)
                guard text.contains("enabled") else { return nil }
                return firstMatch(in: text, pattern: #"enabled\s+([A-Za-z0-9_-]+)"#)
            }
    }

    private static func parseCuaTools(from output: String) -> [String] {
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.contains("cua-driver") else { continue }
            if text.contains("all tools enabled") {
                return readCuaTools + actionCuaTools
            }
            if let includeText = firstMatch(in: text, pattern: #"include only:\s*([^\]]+)"#) {
                return includeText
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }

        return []
    }

    private static func readApprovalMode(from configURL: URL) -> String {
        normalizedConfigScalar(section: "approvals", key: "mode", defaultValue: "manual", configURL: configURL)
    }

    private static func readCronMode(from configURL: URL) -> String {
        normalizedConfigScalar(section: "approvals", key: "cron_mode", defaultValue: "deny", configURL: configURL)
    }

    private static func normalizedConfigScalar(
        section: String,
        key: String,
        defaultValue: String,
        configURL: URL
    ) -> String {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return defaultValue
        }

        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        var inSection = false
        for line in lines {
            if line.hasPrefix("\(section):") {
                inSection = true
                continue
            }

            if inSection, !line.hasPrefix(" "), !line.hasPrefix("\t") {
                break
            }

            guard inSection else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }

            let raw = trimmed
                .dropFirst(key.count + 1)
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .lowercased()
                ?? defaultValue

            if raw == "false" {
                return "off"
            }
            if raw == "true" {
                return "manual"
            }
            return raw.isEmpty ? defaultValue : raw
        }

        return defaultValue
    }

    private static func deriveConfigType(
        enabledToolsets: [String],
        cuaTools: [String],
        approvalMode: String
    ) -> HermesConfigType {
        let enabled = Set(enabledToolsets)
        let cua = Set(cuaTools)
        let readOnly = Set(readOnlyToolsets)
        let localAgent = Set(localAgentToolsets)
        let readCua = Set(readCuaTools)
        let allCua = Set(readCuaTools + actionCuaTools)

        if enabled == readOnly, cua == readCua, approvalMode != "off" {
            return .readOnly
        }

        if enabled == localAgent, cua == allCua {
            return approvalMode == "off" ? .alwaysAllow : .askPerTask
        }

        return .custom
    }

    private static func summary(
        configType: HermesConfigType,
        enabledToolsets: [String],
        cuaTools: [String],
        approvalMode: String,
        cronMode: String,
        configPath: String
    ) -> HermesConfigSummary {
        let readCuaSet = Set(readCuaTools)
        let readCount = cuaTools.filter { readCuaSet.contains($0) }.count
        let actionCount = cuaTools.count - readCount
        let title: String
        let summary: String
        var warnings: [String] = []

        switch configType {
        case .readOnly:
            title = "Read Only"
            summary = "Research, context, memory, skills, planning, and CUA read tools only."
        case .askPerTask:
            title = "Ask Per Task"
            summary = "Local tools and CUA actions are configured, with Hermes dangerous-command approvals on."
        case .alwaysAllow:
            title = "Always Allow"
            summary = "Local tools and CUA actions are configured, with Hermes dangerous-command prompts disabled."
            warnings.append("Hermes approvals.mode is off for dangerous local commands.")
        case .custom:
            title = "Custom"
            summary = "Hermes config is custom. Apply a config type to standardize toolsets and CUA exposure."
            warnings.append("Hermes config does not match an AURA preset.")
        case .unavailable:
            title = "Unavailable"
            summary = "Hermes config has not been checked yet."
        }

        if enabledToolsets.contains("messaging") {
            warnings.append("Messaging tools are enabled in Hermes config; sends still need explicit approval.")
        }

        return HermesConfigSummary(
            configType: configType,
            title: title,
            summary: summary,
            approvalMode: approvalMode,
            cronMode: cronMode,
            cliToolsets: enabledToolsets,
            cuaSurface: cuaSurface(for: cuaTools),
            cuaTools: cuaTools,
            readCuaToolCount: readCount,
            actionCuaToolCount: max(0, actionCount),
            configPath: configPath,
            warnings: warnings
        )
    }

    private static func cuaSurface(for tools: [String]) -> String {
        let toolSet = Set(tools)
        if toolSet.isEmpty {
            return "unconfigured"
        }
        if toolSet == Set(readCuaTools) {
            return "read_only"
        }
        if toolSet == Set(readCuaTools + actionCuaTools) {
            return "action_enabled"
        }
        return "custom"
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[matchRange])
    }
}
