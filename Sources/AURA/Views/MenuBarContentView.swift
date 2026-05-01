import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: AURAStore
    @ObservedObject var sessionManager: MissionSessionManager
    @Environment(\.openWindow) private var openWindow

    init(store: AURAStore) {
        self._store = ObservedObject(wrappedValue: store)
        self._sessionManager = ObservedObject(wrappedValue: store.sessionManager)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .background(AURAVisualStyle.Colors.border)
                .padding(.horizontal, 16)

            primaryAction
                .padding(.horizontal, 16)
                .padding(.top, 14)

            statusSection
                .padding(.horizontal, 16)
                .padding(.top, 14)

            if shouldShowSetupSection {
                setupSection
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }

            footer
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 14)
        }
        .frame(width: 320, alignment: .leading)
        .background(menuPanelBackground)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 9, height: 9)
                .shadow(color: statusDotColor.opacity(0.62), radius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("AURA")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AURAVisualStyle.Colors.textPrimary)

                Text(store.healthState.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AURAVisualStyle.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(sessionManager.statusSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusDotColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var primaryAction: some View {
        Text(primaryHint)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AURAVisualStyle.Colors.textTertiary)
            .lineLimit(2)
    }

    private var statusSection: some View {
        VStack(spacing: 2) {
            MenuBarStatusRow(title: "Hermes", value: store.healthState.title, systemImage: "bolt.horizontal.circle", color: hermesColor)
            MenuBarStatusRow(title: "Sessions", value: sessionManager.statusSummary, systemImage: "point.3.connected.trianglepath.dotted", color: missionColor)
            MenuBarStatusRow(title: "Tools", value: store.hermesToolSurfaceTitle, systemImage: store.hermesToolSurfaceSystemImage, color: AURAVisualStyle.Colors.textSecondary)
            MenuBarStatusRow(title: "Cursor", value: store.isAmbientEnabled ? "Surface on" : "Surface off", systemImage: "cursorarrow.motionlines", color: store.isAmbientEnabled ? AURAVisualStyle.Colors.accent : AURAVisualStyle.Colors.textTertiary)
            MenuBarStatusRow(title: "Host", value: store.cuaStatus.readyForHostControl ? "Ready" : "Setup needed", systemImage: "display.and.arrow.down", color: store.cuaStatus.readyForHostControl ? AURAVisualStyle.Colors.success : AURAVisualStyle.Colors.warning)
        }
        .padding(8)
        .background(AURAVisualStyle.Colors.surface2, in: RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.card, style: .continuous)
                .strokeBorder(AURAVisualStyle.Colors.border.opacity(0.65), lineWidth: 0.75)
        )
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETUP")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AURAVisualStyle.Colors.textTertiary)

            Text(setupCopy)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AURAVisualStyle.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if shouldShowMicrophoneAction {
                    Button(store.microphonePermissionActionTitle ?? "Grant") {
                        Task { await store.handleMicrophonePermissionAction() }
                    }
                    .buttonStyle(AURASecondaryButtonStyle(compact: true))
                    .disabled(store.isRequestingMicrophonePermission)
                } else {
                    Button("Open Setup") {
                        openMainWindow()
                    }
                    .buttonStyle(AURASecondaryButtonStyle(compact: true))
                }

                Button("Refresh") {
                    Task {
                        if store.inputMode == .voice {
                            await store.refreshPermissionStatus()
                        } else {
                            await store.refreshCuaStatus()
                        }
                    }
                }
                .buttonStyle(AURASecondaryButtonStyle(compact: true))
                .disabled(store.isCheckingCua || store.isRequestingMicrophonePermission)
            }
        }
        .padding(12)
        .background(AURAVisualStyle.Colors.surface1, in: RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.card, style: .continuous)
                .strokeBorder(AURAVisualStyle.Colors.border.opacity(0.55), lineWidth: 0.75)
        )
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button("Open") {
                    openMainWindow()
                }
                .buttonStyle(AURASecondaryButtonStyle(compact: true))

                Button("Refresh") {
                    Task { await store.refreshAll() }
                }
                .buttonStyle(AURASecondaryButtonStyle(compact: true))
                .disabled(store.isRunning)

                Toggle("Cursor", isOn: $store.isAmbientEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.canDismissMissionResult {
                Button("Done") {
                    store.dismissMissionResult()
                }
                .buttonStyle(AURAPrimaryButtonStyle(compact: true))
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if sessionManager.hasActiveSessions {
                Button("Cancel Active") {
                    sessionManager.cancelAllActiveSessions()
                }
                .buttonStyle(AURAPrimaryButtonStyle(compact: true))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Button("Doctor") {
                    Task { await store.runDoctor() }
                }
                .buttonStyle(.plain)
                .disabled(store.isRunning)

                Button("Copy Setup") {
                    store.copySetupCommand()
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AURAVisualStyle.Colors.textTertiary)
        }
    }

    private var menuPanelBackground: some View {
        RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.panel, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [AURAVisualStyle.Colors.surface1, AURAVisualStyle.Colors.background],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.panel, style: .continuous)
                    .strokeBorder(AURAVisualStyle.Colors.border.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: AURAVisualStyle.Shadow.panel, radius: 18, x: 0, y: 8)
    }

    private var primaryHint: String {
        if !store.canOpenAmbientEntryPoint {
            return setupCopy
        }

        switch store.inputMode {
        case .text:
            return "Press ⌃⌥⌘A to type a mission in the cursor surface."
        case .voice:
            return "Press ⌃⌥⌘A to speak a mission to AURA."
        }
    }

    private var shouldShowSetupSection: Bool {
        !store.cuaStatus.readyForHostControl || !store.canOpenAmbientEntryPoint
    }

    private var shouldShowMicrophoneAction: Bool {
        store.inputMode == .voice && !store.microphonePermissionStatus.isGranted
    }

    private var setupCopy: String {
        if shouldShowMicrophoneAction {
            return store.microphonePermissionStatus.setupDetail
        }

        if !store.canOpenAmbientEntryPoint {
            return "Finish setup before opening the cursor surface."
        }

        return "Finish host-control setup to let Hermes inspect and operate macOS through AURA."
    }

    private var statusDotColor: Color {
        if store.isRunning { return AURAVisualStyle.Colors.accent }
        switch sessionManager.dominantStatus {
        case .idle:
            return store.healthState == .ready ? AURAVisualStyle.Colors.success : AURAVisualStyle.Colors.warning
        case .running:
            return AURAVisualStyle.Colors.accent
        case .completed:
            return AURAVisualStyle.Colors.success
        case .failed:
            return AURAVisualStyle.Colors.danger
        case .cancelled:
            return AURAVisualStyle.Colors.textTertiary
        }
    }

    private var hermesColor: Color {
        switch store.healthState {
        case .ready:
            return AURAVisualStyle.Colors.success
        case .needsSetup, .warning:
            return AURAVisualStyle.Colors.warning
        case .failed:
            return AURAVisualStyle.Colors.danger
        case .unknown:
            return AURAVisualStyle.Colors.textTertiary
        }
    }

    private var missionColor: Color {
        switch sessionManager.dominantStatus {
        case .idle, .cancelled:
            return AURAVisualStyle.Colors.textTertiary
        case .running:
            return AURAVisualStyle.Colors.accent
        case .completed:
            return AURAVisualStyle.Colors.success
        case .failed:
            return AURAVisualStyle.Colors.danger
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarStatusRow: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AURAVisualStyle.Colors.textTertiary)
                .frame(width: 56, alignment: .leading)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AURAVisualStyle.Colors.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(AURAVisualStyle.Colors.surface3.opacity(0.001), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
