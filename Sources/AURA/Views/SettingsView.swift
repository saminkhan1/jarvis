import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        Form {
            Section("Hermes") {
                LabeledContent("Project Root", value: AURAPaths.projectRoot.path)
                LabeledContent("Wrapper", value: "script/aura-hermes")
                LabeledContent("Hermes Agent", value: AURAPaths.hermesAgentRoot.path)
                LabeledContent("Hermes Home", value: AURAPaths.hermesHome.path)
                Button("Copy Setup Command") {
                    store.copySetupCommand()
                }
            }

            Section("Hermes Tooling") {
                LabeledContent("Tool Surface", value: store.hermesToolSurfaceTitle)
                LabeledContent("Config", value: AURAPaths.hermesHome.appendingPathComponent("config.yaml").path)

                Text(store.hermesToolSurfaceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hermes Voice Mode") {
                Button("Open Hermes Voice Mode") {
                    store.openHermesVoiceMode()
                }

                Text(store.hermesVoiceModeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("CUA Driver") {
                LabeledContent("Status", value: store.cuaStatus.title)
                LabeledContent("Executable", value: store.cuaStatus.executablePath ?? "Not installed")
                LabeledContent("Daemon", value: store.cuaStatus.daemonStatus)
                LabeledContent("Accessibility", value: permissionText(store.cuaStatus.accessibilityGranted))
                LabeledContent("Screen Recording", value: permissionText(store.cuaStatus.screenRecordingGranted))
                LabeledContent("Hermes MCP", value: store.cuaStatus.isMCPRegistered ? "Registered" : "Not registered")

                Button("Refresh") {
                    Task { await store.refreshCuaStatus() }
                }

                Text("Complete CUA setup from the main onboarding screen. System permission prompts are never triggered from workflow or settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560)
    }

    private func permissionText(_ value: Bool?) -> String {
        switch value {
        case .some(true):
            return "Granted"
        case .some(false):
            return "Missing"
        case .none:
            return "Unknown"
        }
    }
}
