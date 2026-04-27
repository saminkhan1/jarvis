import SwiftUI

struct ReadinessCenterView: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Hermes Doctor", systemImage: "stethoscope")
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
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(store.isRefreshingReadiness)
            }

            ScrollView(.vertical) {
                Text(store.readinessOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 120, maxHeight: 320, alignment: .topLeading)
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
