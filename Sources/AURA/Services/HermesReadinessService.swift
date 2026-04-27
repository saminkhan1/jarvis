import Foundation

final class HermesReadinessService {
    private let hermesService: HermesService

    init(hermesService: HermesService = HermesService()) {
        self.hermesService = hermesService
    }

    func refresh(
        cuaStatus: CuaDriverStatus,
        hermesConfigSummary: HermesConfigSummary
    ) async -> [ReadinessItem] {
        let status = await run(["status"])
        let configCheck = await run(["config", "check"])
        let tools = await run(["tools", "list", "--platform", "cli"])
        let mcp = await run(["mcp", "list"])
        let cron = await run(["cron", "list"])
        let skills = await run(["skills", "list"])

        let statusText = status?.combinedOutput ?? ""
        let configText = configCheck?.combinedOutput ?? ""
        let toolsText = tools?.combinedOutput ?? ""
        let mcpText = mcp?.combinedOutput ?? ""
        let cronText = cron?.combinedOutput ?? ""
        let skillsText = skills?.combinedOutput ?? ""
        let enabledToolsets = Set(hermesConfigSummary.cliToolsets)

        return [
            runtimeItem(status: status, statusText: statusText),
            providerItem(status: status, statusText: statusText),
            configTypeItem(hermesConfigSummary),
            hostContextItem(cuaStatus),
            localArtifactItem(enabledToolsets),
            webResearchItem(enabledToolsets, configText: configText),
            browserItem(enabledToolsets, configText: configText),
            appleSkillsItem(skills: skills, skillsText: skillsText),
            messagingItem(enabledToolsets, statusText: statusText),
            cronItem(cron: cron, cronText: cronText),
            externalMCPItem(mcp: mcp, mcpText: mcpText),
            spotifyItem(enabledToolsets, configText: configText, toolsText: toolsText),
        ]
    }

    private func run(_ arguments: [String]) async -> HermesCommandResult? {
        do {
            return try await hermesService.run(arguments: arguments, telemetryEnabled: false)
        } catch {
            return nil
        }
    }

    private func runtimeItem(status: HermesCommandResult?, statusText: String) -> ReadinessItem {
        let isReady = status?.succeeded == true
        return ReadinessItem(
            id: "runtime.hermes",
            group: .runtime,
            title: "Project Hermes",
            status: isReady ? .ready : .blocked,
            detail: isReady ? firstLine(containing: "Project:", in: statusText, fallback: "Project-local Hermes responded.") : "Run ./script/setup.sh, then ./script/aura-hermes status.",
            command: "./script/aura-hermes status",
            systemImage: "bolt.horizontal.circle"
        )
    }

    private func providerItem(status: HermesCommandResult?, statusText: String) -> ReadinessItem {
        guard status?.succeeded == true else {
            return ReadinessItem(
                id: "runtime.provider",
                group: .runtime,
                title: "Provider And Model",
                status: .unknown,
                detail: "Hermes status did not return provider/model details.",
                command: "./script/aura-hermes status",
                systemImage: "cpu"
            )
        }

        let model = firstLine(containing: "Model:", in: statusText, fallback: "Model configured")
        let provider = firstLine(containing: "Provider:", in: statusText, fallback: "Provider configured")
        let codexReady = statusText.contains("OpenAI Codex") && statusText.contains("✓ logged in")
        return ReadinessItem(
            id: "runtime.provider",
            group: .runtime,
            title: "Provider And Model",
            status: codexReady ? .ready : .degraded,
            detail: "\(model) · \(provider)",
            command: "./script/aura-hermes model",
            systemImage: "cpu"
        )
    }

    private func configTypeItem(_ summary: HermesConfigSummary) -> ReadinessItem {
        let status: ReadinessStatus = summary.configType == .custom ? .degraded : .ready
        return ReadinessItem(
            id: "runtime.config_type",
            group: .runtime,
            title: "Config Type",
            status: status,
            detail: summary.detailLine,
            command: "./script/aura-hermes tools list --platform cli",
            systemImage: summary.configType.systemImage
        )
    }

    private func hostContextItem(_ cuaStatus: CuaDriverStatus) -> ReadinessItem {
        ReadinessItem(
            id: "host.cua",
            group: .host,
            title: "Host Context And CUA",
            status: cuaStatus.readyForHostControl ? .ready : .blocked,
            detail: cuaStatus.readyForHostControl ? "CUA daemon, permissions, and Hermes MCP registration are ready." : cuaStatus.issues.joined(separator: " "),
            command: "cua-driver status && ./script/aura-hermes mcp test cua-driver",
            systemImage: "display.and.arrow.down"
        )
    }

    private func localArtifactItem(_ enabledToolsets: Set<String>) -> ReadinessItem {
        let hasLocalWrites = enabledToolsets.isSuperset(of: ["terminal", "file", "code_execution"])
        return ReadinessItem(
            id: "local.artifacts",
            group: .local,
            title: "Local Artifacts",
            status: hasLocalWrites ? .ready : .degraded,
            detail: hasLocalWrites ? "Terminal, file, and code execution toolsets are enabled in Hermes config." : "Local write/build tools are disabled by the current Hermes config type.",
            command: "./script/aura-hermes tools list --platform cli",
            systemImage: "folder.badge.gearshape"
        )
    }

    private func webResearchItem(_ enabledToolsets: Set<String>, configText: String) -> ReadinessItem {
        guard enabledToolsets.contains("web") else {
            return ReadinessItem(
                id: "web.research",
                group: .web,
                title: "Web Research",
                status: .degraded,
                detail: "The web toolset is disabled in Hermes config.",
                command: "./script/aura-hermes tools enable --platform cli web",
                systemImage: "network"
            )
        }

        let missingProviders = configText.contains("EXA_API_KEY")
            || configText.contains("TAVILY_API_KEY")
            || configText.contains("FIRECRAWL_API_KEY")
            || configText.contains("PARALLEL_API_KEY")
        return ReadinessItem(
            id: "web.research",
            group: .web,
            title: "Web Research",
            status: missingProviders ? .degraded : .ready,
            detail: missingProviders ? "Web toolset is enabled, but Hermes reports missing optional web provider keys." : "Web toolset and provider config are available.",
            command: "./script/aura-hermes config check",
            systemImage: "network"
        )
    }

    private func browserItem(_ enabledToolsets: Set<String>, configText: String) -> ReadinessItem {
        guard enabledToolsets.contains("browser") else {
            return ReadinessItem(
                id: "web.browser",
                group: .web,
                title: "Browser Automation",
                status: .degraded,
                detail: "The browser toolset is disabled in Hermes config.",
                command: "./script/aura-hermes tools enable --platform cli browser",
                systemImage: "globe"
            )
        }

        let missingBrowser = configText.contains("BROWSERBASE_API_KEY")
            || configText.contains("BROWSER_USE_API_KEY")
            || configText.contains("CAMOFOX_URL")
        return ReadinessItem(
            id: "web.browser",
            group: .web,
            title: "Browser Automation",
            status: missingBrowser ? .degraded : .ready,
            detail: missingBrowser ? "Browser toolset is enabled, but Hermes reports missing browser provider/CDP setup." : "Browser provider config is available.",
            command: "./script/aura-hermes config check",
            systemImage: "globe"
        )
    }

    private func appleSkillsItem(skills: HermesCommandResult?, skillsText: String) -> ReadinessItem {
        let hasAppleSkills = skills?.succeeded == true
            && skillsText.contains("apple-reminders")
            && skillsText.contains("apple-notes")
            && skillsText.contains("imessage")
        return ReadinessItem(
            id: "apps.apple_skills",
            group: .apps,
            title: "Apple App Skills",
            status: hasAppleSkills ? .ready : .degraded,
            detail: hasAppleSkills ? "Apple Notes, Reminders, iMessage, and Find My skills are installed as Hermes skills." : "Apple app skills were not found in Hermes skills list.",
            command: "./script/aura-hermes skills list",
            systemImage: "apple.logo"
        )
    }

    private func messagingItem(_ enabledToolsets: Set<String>, statusText: String) -> ReadinessItem {
        let enabled = enabledToolsets.contains("messaging")
        let configured = statusText.contains("Messaging Platforms") && !statusText.contains("Telegram      ✗ not configured")
        return ReadinessItem(
            id: "apps.messaging",
            group: .apps,
            title: "Messaging",
            status: configured && enabled ? .ready : .degraded,
            detail: configured && enabled ? "Hermes messaging platform config is present." : "Messaging is disabled or unconfigured; drafts remain safe, sends require explicit approval.",
            command: "./script/aura-hermes status",
            systemImage: "paperplane"
        )
    }

    private func cronItem(cron: HermesCommandResult?, cronText: String) -> ReadinessItem {
        ReadinessItem(
            id: "automation.cron",
            group: .automation,
            title: "Hermes Cron",
            status: cron?.succeeded == true ? .ready : .degraded,
            detail: cron?.succeeded == true ? firstLine(in: cronText, fallback: "Cron list command is available.") : "Hermes cron list failed.",
            command: "./script/aura-hermes cron list",
            systemImage: "calendar.badge.clock"
        )
    }

    private func externalMCPItem(mcp: HermesCommandResult?, mcpText: String) -> ReadinessItem {
        let hasOnlyCUA = mcpText.contains("cua-driver") && !mcpText.localizedCaseInsensitiveContains("github")
        let hasExternal = mcp?.succeeded == true && !hasOnlyCUA
        return ReadinessItem(
            id: "automation.external_mcp",
            group: .automation,
            title: "External MCP",
            status: hasExternal ? .ready : .degraded,
            detail: hasExternal ? "At least one non-CUA MCP server is configured." : "Only CUA MCP is configured. Add GitHub or filesystem MCP in Hermes config when needed.",
            command: "./script/aura-hermes mcp list",
            systemImage: "point.3.connected.trianglepath.dotted"
        )
    }

    private func spotifyItem(_ enabledToolsets: Set<String>, configText: String, toolsText: String) -> ReadinessItem {
        let enabled = enabledToolsets.contains("spotify") || toolsText.contains("spotify")
        return ReadinessItem(
            id: "apps.spotify",
            group: .apps,
            title: "Spotify",
            status: enabled ? .degraded : .degraded,
            detail: enabled ? "Spotify toolset exists, but provider/account setup is not confirmed." : "Spotify remains optional and disabled in Hermes tool config.",
            command: "./script/aura-hermes tools list --platform cli",
            systemImage: "music.note"
        )
    }

    private func firstLine(containing needle: String, in text: String, fallback: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { $0.contains(needle) } ?? fallback
    }

    private func firstLine(in text: String, fallback: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? fallback
    }
}
