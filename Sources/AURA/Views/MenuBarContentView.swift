import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: AURAStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AURA")
                .font(.headline)

            if !store.cuaStatus.readyForHostControl {
                Text("Setup required")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text(store.cuaStatus.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Button("Open Setup") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Button("Refresh Setup") {
                    Task { await store.refreshCuaStatus() }
                }
                .disabled(store.isCheckingCua)

                Button("Copy CUA Install") {
                    store.copyCuaInstallCommand()
                }

                Divider()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            } else {
                Text(store.healthState.title)
                    .foregroundStyle(.secondary)

                Text("Mission: \(store.missionStatus.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Policy: \(store.automationPolicy.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(store.isAmbientEnabled ? "Cursor surface on" : "Cursor surface off")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("CUA ready")
                    .font(.caption)
                    .foregroundStyle(.green)

                Divider()

                Button("Open AURA") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Button("Refresh") {
                    Task { await store.refreshAll() }
                }
                .disabled(store.isRunning)

                Button("New Mission") {
                    store.showAmbientEntryPoint()
                }
                .keyboardShortcut("a", modifiers: [.control, .option, .command])
                .disabled(!store.canOpenAmbientEntryPoint)

                Toggle("Cursor Indicator", isOn: $store.isAmbientEnabled)

                Button("Cancel Mission") {
                    store.cancelMission()
                }
                .disabled(!store.canCancelMission)

                if store.pendingApproval != nil {
                    Button("Approve & Continue") {
                        Task { await store.approvePendingAction() }
                    }
                    .disabled(!store.canApproveMission)

                    Button("Deny Approval") {
                        store.denyPendingApproval()
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
        }
        .padding(.vertical, 4)
        .frame(width: 220, alignment: .leading)
    }
}
