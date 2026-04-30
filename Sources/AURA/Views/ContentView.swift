import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.shouldShowCuaOnboarding {
                    OnboardingGateView(store: store)
                }
                DashboardHeader(store: store)
                StatusGrid(store: store)
                MissionConfigurationCard(store: store)
                ReadinessCenterView(store: store)
                MissionRunnerView(store: store)
                HermesSessionsCard(store: store)
                HermesControlCard(store: store)
                MissionOutputView(store: store)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refreshPermissionStatus() }
        }
    }
}

private struct OnboardingGateView: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Host Control Setup")
                        .font(.title.bold())
                    Text("Hermes chat stays available while you finish CUA or microphone setup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if store.isCheckingCua || store.isRunningCuaOnboarding || store.isRequestingMicrophonePermission {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(store.cuaOnboardingMessage)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Mission Input")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                MissionInputModePicker(store: store)
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Hermes Config")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(store.hermesToolSurfaceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 6) {
                CuaSetupRow(
                    title: "AURA Host Control",
                    detail: store.cuaStatus.isInstalled
                        ? store.cuaStatus.executablePath ?? "Installed"
                        : "Install CUA support before host control can start.",
                    isComplete: store.cuaStatus.isInstalled,
                    actionTitle: store.cuaStatus.isInstalled ? nil : "Copy Setup"
                ) {
                    store.copyCuaInstallCommand()
                }

                CuaSetupRow(
                    title: "Host-Control Helper",
                    detail: store.cuaStatus.daemonStatus,
                    isComplete: store.cuaStatus.daemonRunning,
                    actionTitle: store.cuaStatus.isInstalled && !store.cuaStatus.daemonRunning ? "Start" : nil
                ) {
                    Task { await store.startCuaDriverDaemon() }
                }

                CuaSetupRow(
                    title: "Accessibility",
                    detail: "Grant AURA access to inspect and target app UI.",
                    isComplete: store.cuaStatus.accessibilityGranted == true,
                    actionTitle: canRequestPermissions && store.cuaStatus.accessibilityGranted != true ? "Grant" : nil
                ) {
                    Task { await store.requestCuaDriverPermissions(focusing: .accessibility) }
                }

                CuaSetupRow(
                    title: "Screen Recording",
                    detail: "Grant AURA access to inspect visible screen content.",
                    isComplete: store.cuaStatus.screenRecordingGranted == true,
                    actionTitle: canRequestPermissions && store.cuaStatus.screenRecordingGranted != true ? "Grant" : nil
                ) {
                    Task { await store.requestCuaDriverPermissions(focusing: .screenRecording) }
                }

                if store.inputMode == .voice {
                    CuaSetupRow(
                        title: "Microphone",
                        detail: store.microphonePermissionStatus.setupDetail,
                        isComplete: store.microphonePermissionStatus.isGranted,
                        actionTitle: store.microphonePermissionActionTitle
                    ) {
                        Task { await store.handleMicrophonePermissionAction() }
                    }
                }

                CuaSetupRow(
                    title: "Hermes computer_use",
                    detail: "Enable Hermes-owned computer-use for CUA missions.",
                    isComplete: store.cuaStatus.isHermesComputerUseEnabled,
                    actionTitle: canEnableHermesComputerUse ? "Enable" : nil
                ) {
                    Task { await store.enableHermesComputerUse() }
                }
            }

            HStack {
                Button {
                    Task { await store.refreshCuaStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isCheckingCua || store.isRunningCuaOnboarding)

                Button {
                    store.copyCuaInstallCommand()
                } label: {
                    Label("Copy Setup", systemImage: "doc.on.doc")
                }

                Button {
                    store.copyCuaDaemonCommand()
                } label: {
                    Label("Copy Daemon", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var canRequestPermissions: Bool {
        store.cuaStatus.isInstalled && store.cuaStatus.daemonRunning
    }

    private var canEnableHermesComputerUse: Bool {
        store.cuaStatus.isInstalled
            && store.cuaStatus.daemonRunning
            && store.cuaStatus.permissionsReady
            && !store.cuaStatus.isHermesComputerUseEnabled
    }
}

private struct CuaSetupRow: View {
    let title: String
    let detail: String
    let isComplete: Bool
    let actionTitle: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(isComplete ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

private struct DashboardHeader: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AURA")
                    .font(.title.bold())
                Text("Native macOS surface for Hermes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.openMissionInput()
            } label: {
                Label(store.inputMode.actionTitle, systemImage: store.inputMode.systemImage)
            }
            .keyboardShortcut("a", modifiers: [.control, .option, .command])
            .disabled(!store.canOpenAmbientEntryPoint)
            .accessibilityIdentifier("aura.newMission")

            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRunning)
            .accessibilityIdentifier("aura.refresh")
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StatusGrid: View {
    @ObservedObject var store: AURAStore
    @ObservedObject var sessionManager: MissionSessionManager

    init(store: AURAStore) {
        self._store = ObservedObject(wrappedValue: store)
        self._sessionManager = ObservedObject(wrappedValue: store.sessionManager)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            StatusTile(title: "Hermes", value: store.healthState.title, systemImage: "bolt.horizontal.circle", color: healthColor)
            StatusTile(title: "Sessions", value: sessionManager.statusSummary, systemImage: "point.3.connected.trianglepath.dotted", color: missionColor)
            StatusTile(title: "Input", value: store.inputMode.title, systemImage: store.inputMode.systemImage, color: .secondary)
            StatusTile(title: "Tools", value: store.hermesToolSurfaceTitle, systemImage: store.hermesToolSurfaceSystemImage, color: .secondary)
            StatusTile(title: "CUA", value: store.cuaStatus.title, systemImage: "display.and.arrow.down", color: store.cuaStatus.readyForHostControl ? .green : .orange)
        }
    }

    private var healthColor: Color {
        if store.isRunning { return .blue }

        switch store.healthState {
        case .ready:
            return .green
        case .needsSetup, .warning:
            return .orange
        case .failed:
            return .red
        case .unknown:
            return .secondary
        }
    }

    private var missionColor: Color {
        switch sessionManager.dominantStatus {
        case .idle, .cancelled:
            return .secondary
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

}

private struct StatusTile: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MissionConfigurationCard: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Mission Configuration", systemImage: "slider.horizontal.3")
                    .font(.headline)

                Spacer()

                if store.isRefreshingHermesConfig {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await store.refreshHermesConfigStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshingHermesConfig)
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Input")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MissionInputModePicker(store: store)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Config")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(store.hermesToolSurfaceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack {
                Button {
                    store.openHermesConfigFile()
                } label: {
                    Label("Open Config", systemImage: "doc.text")
                }

                Button {
                    store.revealHermesConfigFile()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }
            .font(.caption)

            ScrollView(.vertical) {
                Text(store.hermesConfigOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 90, maxHeight: 220, alignment: .topLeading)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HermesSessionsCard: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Hermes Sessions", systemImage: "clock.arrow.circlepath")
                    .font(.headline)

                Spacer()

                if let updated = store.hermesSessionsUpdated {
                    Text(updated, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Refresh") {
                    Task { await store.refreshHermesSessions() }
                }
                .disabled(store.isRunning)
            }

            Text(store.hermesSessionsOutput)
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.hermesSessionSummaries.isEmpty {
                if store.hermesSessionsOutput.lowercased().contains("failed") {
                    ContentUnavailableView(
                        "Hermes session history unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("AURA could not load Hermes-owned session history just now.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView(
                        "No recent AURA sessions",
                        systemImage: "clock.badge.xmark",
                        description: Text("Hermes has no recent AURA-tagged sessions to show yet.")
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.hermesSessionSummaries) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(session.preview)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                Spacer()
                                if session.id == store.currentHermesSessionID {
                                    Text("Current")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                                }
                            }

                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                    Text(session.lastActive, style: .relative)
                                }
                                if session.messageCount > 0 {
                                    Text("\(session.messageCount) msg")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if store.hermesSessionsOutput.lowercased().contains("failed") {
                DisclosureGroup("Diagnostics") {
                    ScrollView(.horizontal) {
                        Text(store.hermesSessionsOutput)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.top, 6)
                    }
                }
                .font(.caption)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HermesControlCard: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hermes Runtime")
                .font(.headline)

            HStack {
                Text("Wrapper")
                    .foregroundStyle(.secondary)
                    .frame(width: 98, alignment: .leading)
                Text("script/aura-hermes")
                    .textSelection(.enabled)
                Spacer()
            }
            .font(.caption)

            HStack {
                Text("Hermes")
                    .foregroundStyle(.secondary)
                    .frame(width: 98, alignment: .leading)
                Text(AURAPaths.hermesAgentRoot.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
            }
            .font(.caption)

            HStack {
                Text("Hermes Home")
                    .foregroundStyle(.secondary)
                    .frame(width: 98, alignment: .leading)
                Text(AURAPaths.hermesHome.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
            }
            .font(.caption)

            HStack {
                Text("Version")
                    .foregroundStyle(.secondary)
                    .frame(width: 98, alignment: .leading)
                Text(store.hermesVersion)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
            }
            .font(.caption)

            HStack {
                Button("Run Doctor") {
                    Task { await store.runDoctor() }
                }

                Button("Copy Setup") {
                    store.copySetupCommand()
                }

                Button("Reveal Project") {
                    store.openProjectFolder()
                }
            }
            .disabled(store.isRunning)

            Text("Mission input and Hermes config type can be changed from the dashboard, Settings, or onboarding.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
