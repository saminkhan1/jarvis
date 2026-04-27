import SwiftUI

struct ReadinessCenterView: View {
    @ObservedObject var store: AURAStore

    private var groupedItems: [(ReadinessGroup, [ReadinessItem])] {
        ReadinessGroup.allCases.compactMap { group in
            let items = store.readinessItems.filter { $0.group == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Readiness Center", systemImage: "checklist")
                    .font(.headline)

                Spacer()

                if let updated = store.readinessUpdated {
                    Text(updated, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.isRefreshingReadiness {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await store.refreshConnectionReadiness() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshingReadiness)
            }

            if groupedItems.isEmpty {
                Text("Run a readiness refresh to inspect project-local Hermes, CUA, tools, skills, web, messaging, cron, and MCP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedItems, id: \.0.id) { group, items in
                        ReadinessGroupSection(group: group, items: items)
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ReadinessGroupSection: View {
    let group: ReadinessGroup
    let items: [ReadinessItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.rawValue.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ReadinessRow(item: item)

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct ReadinessRow: View {
    let item: ReadinessItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.status.systemImage)
                .font(.caption)
                .foregroundStyle(statusColor)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(item.title, systemImage: item.systemImage)
                        .font(.callout.weight(.medium))

                    Text(item.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }

                Text(item.detail.isEmpty ? "No detail returned." : item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let command = item.command {
                    Text(command)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch item.status {
        case .ready:
            return .green
        case .degraded:
            return .orange
        case .blocked:
            return .red
        case .unknown:
            return .secondary
        }
    }
}
