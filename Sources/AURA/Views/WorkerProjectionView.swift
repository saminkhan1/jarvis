import SwiftUI

struct WorkerProjectionView: View {
    @ObservedObject var store: AURAStore

    private var recentWorkers: [WorkerRun] {
        Array(store.workerRuns.suffix(4))
    }

    private var activeWorkers: [WorkerRun] {
        store.workerRuns.filter { $0.status == .running || $0.status == .needsApproval }
    }

    var body: some View {
        if !store.workerRuns.isEmpty || !store.artifacts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Label("Workers", systemImage: "square.stack.3d.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    WorkerBadgeStack(workers: activeWorkers)
                }

                if !recentWorkers.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 8)], spacing: 8) {
                        ForEach(recentWorkers) { worker in
                            WorkerTile(worker: worker)
                        }
                    }
                }

                if !store.artifacts.isEmpty {
                    ArtifactStrip(store: store, artifacts: store.artifacts)
                }
            }
        }
    }
}

private struct WorkerTile: View {
    let worker: WorkerRun
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: worker.domain.systemImage)
                    .foregroundStyle(statusColor)
                Text(worker.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(worker.status.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor)

            Text(worker.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(minHeight: 86, alignment: .topLeading)
        .background(isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if worker.attachedApprovalID != nil {
                Image(systemName: "hand.raised.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(7)
            }
        }
        .help(worker.detail)
        .onHover { isHovering = $0 }
    }

    private var statusColor: Color {
        color(for: worker.status)
    }
}

private struct WorkerBadgeStack: View {
    let workers: [WorkerRun]

    var body: some View {
        HStack(spacing: -3) {
            ForEach(Array(workers.prefix(5))) { worker in
                Image(systemName: worker.domain.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(color(for: worker.status), in: Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    .help("\(worker.title): \(worker.status.title)")
            }

            if workers.count > 5 {
                Text("+\(workers.count - 5)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
            }
        }
        .frame(minWidth: 22, alignment: .trailing)
    }
}

private struct ArtifactStrip: View {
    @ObservedObject var store: AURAStore
    let artifacts: [AURAArtifact]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Artifacts", systemImage: "tray.full")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(artifacts) { artifact in
                HStack(spacing: 8) {
                    Image(systemName: artifact.type.systemImage)
                        .foregroundStyle(artifact.exists ? Color.accentColor : Color.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(artifact.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(artifact.exists ? artifact.path : "Missing: \(artifact.path)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    Button {
                        store.openArtifact(artifact)
                    } label: {
                        Image(systemName: artifact.type == .app ? "play.fill" : "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help(artifact.type == .app ? "Open app" : "Open artifact")
                    .disabled(!artifact.exists)

                    Button {
                        store.revealArtifact(artifact)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")

                    Button {
                        store.continueWithArtifact(artifact)
                    } label: {
                        Image(systemName: "arrowshape.turn.up.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Continue with this artifact")
                }
                .padding(.vertical, 5)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private func color(for status: WorkerStatus) -> Color {
    switch status {
    case .queued:
        return .secondary
    case .running:
        return .blue
    case .needsApproval:
        return .orange
    case .completed:
        return .green
    case .failed:
        return .red
    case .cancelled:
        return .secondary
    }
}
