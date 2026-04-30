import SwiftUI

struct MissionRunnerView: View {
    @ObservedObject var store: AURAStore
    @ObservedObject var sessionManager: MissionSessionManager

    init(store: AURAStore) {
        self._store = ObservedObject(wrappedValue: store)
        self._sessionManager = ObservedObject(wrappedValue: store.sessionManager)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label("Mission Sessions", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)

                Spacer()

                Toggle("Cursor Surface", isOn: $store.isAmbientEnabled)
                    .toggleStyle(.switch)

                MissionStatusPill(status: sessionManager.dominantStatus)
            }

            Text("Press ⌃⌥⌘A to open the cursor composer near your pointer. Each request starts its own Hermes session, so you can send another while one is still running.")
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

            HStack {
                Button {
                    store.openMissionInput()
                } label: {
                    Label(store.inputMode.actionTitle, systemImage: store.inputMode.systemImage)
                }
                .keyboardShortcut("a", modifiers: [.control, .option, .command])
                .disabled(!store.canOpenAmbientEntryPoint)
                .accessibilityIdentifier("aura.openPanel")

                Spacer()

                if store.canDismissMissionResult {
                    Button {
                        store.dismissMissionResult()
                    } label: {
                        Label("Done", systemImage: "checkmark.circle")
                    }
                } else if sessionManager.hasActiveSessions {
                    Button(role: .cancel) {
                        sessionManager.cancelAllActiveSessions()
                    } label: {
                        Label("Cancel Active", systemImage: "stop.fill")
                    }
                }
            }

            if sessionManager.sessions.isEmpty {
                Text("No mission sessions yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sessionManager.sessions) { session in
                        MissionSessionRow(
                            session: session,
                            isSelected: session.id == sessionManager.selectedSessionID,
                            select: {
                                sessionManager.selectSession(session.id)
                            },
                            cancel: {
                                sessionManager.cancelSession(session.id)
                            },
                            dismiss: {
                                sessionManager.removeSession(session.id)
                            }
                        )
                    }
                }
            }

            if let snapshot = store.contextSnapshot {
                ContextSnapshotView(snapshot: snapshot)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MissionOutputView: View {
    @ObservedObject var store: AURAStore
    @ObservedObject var sessionManager: MissionSessionManager

    init(store: AURAStore) {
        self._store = ObservedObject(wrappedValue: store)
        self._sessionManager = ObservedObject(wrappedValue: store.sessionManager)
    }

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

            Text(outputSubtitle)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(outputText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var outputSession: MissionSession? {
        sessionManager.selectedSession ?? sessionManager.latestSession
    }

    private var outputSubtitle: String {
        if let outputSession {
            return "\(outputSession.status.title) · \(outputSession.displayTitle)"
        }

        return store.lastCommand
    }

    private var outputText: String {
        guard let outputSession else {
            return store.missionOutput.isEmpty ? "No output." : store.missionOutput
        }

        return outputSession.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? outputSession.status.title
            : outputSession.output
    }
}

private struct MissionSessionRow: View {
    @ObservedObject var session: MissionSession
    let isSelected: Bool
    let select: () -> Void
    let cancel: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            switch session.status {
            case .running:
                Button(role: .cancel, action: cancel) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cancel session")
            case .completed, .failed, .cancelled:
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss session")
            case .idle:
                EmptyView()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }

    private var detail: String {
        if let startedAt = session.startedAt, session.status == .running {
            return "Started \(startedAt.formatted(date: .omitted, time: .shortened))"
        }

        if let finishedAt = session.finishedAt {
            return "\(session.status.title) \(finishedAt.formatted(date: .omitted, time: .shortened))"
        }

        return session.status.title
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var icon: String {
        switch session.status {
        case .idle:
            return "circle"
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
        switch session.status {
        case .idle:
            return .secondary
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
