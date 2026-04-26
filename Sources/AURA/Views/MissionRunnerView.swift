import SwiftUI

struct MissionRunnerView: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label("Current Mission", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)

                Spacer()

                Toggle("Indicator", isOn: $store.isAmbientEnabled)
                    .toggleStyle(.switch)

                MissionStatusPill(status: store.missionStatus)
            }

            Text("Press ⌃⌥⌘A to expand the cursor composer in place. The cursor bot stays anchored near your pointer and turns into the prompt when you need it.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !store.missionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Goal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(store.missionGoal)
                        .font(.callout)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Label("Tools: \(store.hermesToolSurfaceTitle)", systemImage: store.hermesToolSurfaceSystemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let approval = store.pendingApproval {
                ApprovalRequestCard(store: store, approval: approval)
            }

            HStack {
                Button {
                    store.showAmbientEntryPoint()
                } label: {
                    Label("Open Composer", systemImage: "sparkle.magnifyingglass")
                }
                .keyboardShortcut("a", modifiers: [.control, .option, .command])
                .disabled(!store.canOpenAmbientEntryPoint)
                .accessibilityIdentifier("aura.openPanel")

                Spacer()

                Button(role: .cancel) {
                    store.cancelMission()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .disabled(!store.canCancelMission)
            }

            if let snapshot = store.contextSnapshot {
                ContextSnapshotView(snapshot: snapshot)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ApprovalRequestCard: View {
    @ObservedObject var store: AURAStore
    let approval: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Approval Needed", systemImage: "hand.raised")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(approval.title)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Hermes config controls whether the approved action is available.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(role: .cancel) {
                    store.denyPendingApproval()
                } label: {
                    Label("Deny", systemImage: "xmark")
                }

                Spacer()

                Button {
                    Task { await store.approvePendingAction() }
                } label: {
                    Label("Approve & Continue", systemImage: "checkmark")
                }
                .disabled(!store.canApproveMission)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MissionOutputView: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Mission Output", systemImage: "text.alignleft")
                    .font(.headline)

                Spacer()

                if let lastUpdated = store.lastUpdated {
                    Text(lastUpdated, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(store.lastCommand)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(store.missionOutput.isEmpty ? "No output." : store.missionOutput)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ContextSnapshotView: View {
    let snapshot: ContextSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Context")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(snapshot.markdownSummary)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ReadinessRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value.isEmpty ? "Unknown" : value)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.caption)
    }
}

private struct MissionStatusPill: View {
    let status: MissionStatus

    var body: some View {
        Label(status.title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var icon: String {
        switch status {
        case .idle:
            return "circle"
        case .needsApproval:
            return "hand.raised"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        case .cancelled:
            return "stop.circle"
        }
    }

    private var color: Color {
        switch status {
        case .idle:
            return .secondary
        case .needsApproval:
            return .orange
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        }
    }
}
