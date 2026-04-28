import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: AURAStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AURA")
                .font(.headline)

            Text(store.healthState.title)
                .foregroundStyle(.secondary)

            Text("Mission: \(store.missionStatus.title)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Tools: \(store.hermesToolSurfaceTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(store.isAmbientEnabled ? "Cursor surface on" : "Cursor surface off")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(store.cuaStatus.readyForHostControl ? "CUA ready" : "CUA setup recommended")
                .font(.caption)
                .foregroundStyle(store.cuaStatus.readyForHostControl ? .green : .orange)

            Divider()

            Button("Open AURA") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Refresh") {
                Task { await store.refreshAll() }
            }
            .disabled(store.isRunning)

            Button(store.inputMode.actionTitle) {
                store.openMissionInput()
            }
            .keyboardShortcut("a", modifiers: [.control, .option, .command])
            .disabled(!store.canOpenAmbientEntryPoint)

            Toggle("Cursor Surface", isOn: $store.isAmbientEnabled)

            if !store.cuaStatus.readyForHostControl {
                Button("Open Setup") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Button("Refresh Setup") {
                    Task { await store.refreshCuaStatus() }
                }
                .disabled(store.isCheckingCua)
            }

            if store.canDismissMissionResult {
                Button("Done") {
                    store.dismissMissionResult()
                }
            } else if store.canCancelMission {
                Button("Cancel Mission") {
                    store.cancelMission()
                }
            }

            Button("Run Doctor") {
                Task { await store.runDoctor() }
            }
            .disabled(store.isRunning)

            Button("Copy Setup") {
                store.copySetupCommand()
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
        .frame(width: 220, alignment: .leading)
    }
}
