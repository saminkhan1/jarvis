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

                HStack {
                    Button("Refresh Config") {
                        Task { await store.refreshHermesConfigStatus() }
                    }

                    Button("Open Config") {
                        store.openHermesConfigFile()
                    }

                    Button("Reveal Config") {
                        store.revealHermesConfigFile()
                    }
                }

                Text(store.hermesToolSurfaceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(store.hermesConfigOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("Mission Input") {
                MissionInputModePicker(store: store)
                LabeledContent("Microphone", value: store.microphonePermissionStatus.title)
                Text(store.microphonePermissionStatus.setupDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("CUA Driver") {
                LabeledContent("Status", value: store.cuaStatus.title)
                LabeledContent("Executable", value: store.cuaStatus.executablePath ?? "Not installed")
                LabeledContent("Daemon", value: store.cuaStatus.daemonStatus)
                LabeledContent("Accessibility", value: permissionText(store.cuaStatus.accessibilityGranted))
                LabeledContent("Screen Recording", value: permissionText(store.cuaStatus.screenRecordingGranted))
                LabeledContent("Hermes computer_use", value: store.cuaStatus.isHermesComputerUseEnabled ? "Enabled" : "Disabled")

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
