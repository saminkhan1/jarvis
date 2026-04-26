import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.shouldShowCuaOnboarding {
                    OnboardingGateView(store: store)
                } else {
                    DashboardHeader(store: store)
                    StatusGrid(store: store)
                    MissionRunnerView(store: store)
                    HermesSessionsCard(store: store)
                    HermesControlCard(store: store)
                    MissionOutputView(store: store)
                }
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
                    Text("AURA Setup Required")
                        .font(.title.bold())
                    Text("AURA is locked until Cua Driver host control is installed, permissioned, running, and registered with project Hermes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if store.isCheckingCua || store.isRunningCuaOnboarding {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(store.cuaOnboardingMessage)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                CuaSetupRow(
                    title: "Cua Driver",
                    detail: store.cuaStatus.isInstalled
                        ? store.cuaStatus.executablePath ?? "Installed"
                        : "Install Cua Driver before AURA can start.",
                    isComplete: store.cuaStatus.isInstalled,
                    actionTitle: store.cuaStatus.isInstalled ? nil : "Copy Install"
                ) {
                    store.copyCuaInstallCommand()
                }

                CuaSetupRow(
                    title: "Cua Driver Daemon",
                    detail: store.cuaStatus.daemonStatus,
                    isComplete: store.cuaStatus.daemonRunning,
                    actionTitle: store.cuaStatus.isInstalled && !store.cuaStatus.daemonRunning ? "Start" : nil
                ) {
                    Task { await store.startCuaDriverDaemon() }
                }

                CuaSetupRow(
                    title: "Accessibility",
                    detail: "Grant CuaDriver.app access to inspect and target app UI.",
                    isComplete: store.cuaStatus.accessibilityGranted == true,
                    actionTitle: canRequestPermissions && store.cuaStatus.accessibilityGranted != true ? "Grant" : nil
                ) {
                    Task { await store.requestCuaDriverPermissions(focusing: .accessibility) }
                }

                CuaSetupRow(
                    title: "Screen Recording",
                    detail: "Grant CuaDriver.app access to inspect visible screen content.",
                    isComplete: store.cuaStatus.screenRecordingGranted == true,
                    actionTitle: canRequestPermissions && store.cuaStatus.screenRecordingGranted != true ? "Grant" : nil
                ) {
                    Task { await store.requestCuaDriverPermissions(focusing: .screenRecording) }
                }

                CuaSetupRow(
                    title: "Hermes MCP",
                    detail: "Register AURA's CUA daemon proxy with project-local Hermes.",
                    isComplete: store.cuaStatus.isMCPRegistered,
                    actionTitle: canRegisterMCP ? "Register" : nil
                ) {
                    Task { await store.registerCuaDriverWithHermes() }
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
                    Label("Copy Install", systemImage: "doc.on.doc")
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

    private var canRegisterMCP: Bool {
        store.cuaStatus.isInstalled
            && store.cuaStatus.daemonRunning
            && store.cuaStatus.permissionsReady
            && !store.cuaStatus.isMCPRegistered
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
                Text("Native cockpit for Hermes missions, approvals, and host-lane readiness.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.showAmbientEntryPoint()
            } label: {
                Label("New Mission", systemImage: "plus")
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

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            StatusTile(title: "Hermes", value: store.healthState.title, systemImage: "bolt.horizontal.circle", color: healthColor)
            StatusTile(title: "Mission", value: store.missionStatus.title, systemImage: "point.3.connected.trianglepath.dotted", color: missionColor)
            StatusTile(title: "Policy", value: store.automationPolicy.title, systemImage: store.automationPolicy.systemImage, color: .secondary)
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
        switch store.missionStatus {
        case .idle, .cancelled:
            return .secondary
        case .needsApproval:
            return .orange
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

            if store.hermesSessions.isEmpty {
                Text(store.hermesSessionsOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.hermesSessions.enumerated()), id: \.element.id) { index, session in
                        HermesSessionRow(session: session)

                        if index < store.hermesSessions.count - 1 {
                            Divider()
                        }
                    }
                }
                .textSelection(.enabled)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HermesSessionRow: View {
    let session: HermesSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(session.preview)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text(session.statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text(session.id)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)

                Text(session.source)
                Text(session.model)
                Text("\(session.messageCount) messages")

                if session.toolCallCount > 0 {
                    Text("\(session.toolCallCount) tools")
                }

                Spacer()

                if let date = session.displayDate {
                    Text(date, style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 9)
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
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
