import SwiftUI

struct HermesConfigTypePicker: View {
    @ObservedObject var store: AURAStore

    private var pickerCases: [HermesConfigType] {
        var cases = HermesConfigType.selectableCases
        let current = store.hermesConfigSummary.configType
        if !current.isSelectable {
            cases.append(current)
        }
        return cases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                "Config Type",
                selection: Binding(
                    get: { store.hermesConfigSummary.configType },
                    set: { newValue in
                        Task { await store.applyHermesConfigType(newValue) }
                    }
                )
            ) {
                ForEach(pickerCases) { configType in
                    Label(configType.title, systemImage: configType.systemImage)
                        .tag(configType)
                        .disabled(!configType.isSelectable)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.isApplyingHermesConfig || store.isRunning)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: store.hermesConfigSummary.configType.systemImage)
                    .foregroundStyle(configColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.hermesConfigSummary.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(store.hermesConfigSummary.detailLine)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    ForEach(store.hermesConfigSummary.warnings.prefix(2), id: \.self) { warning in
                        Text(warning)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var configColor: Color {
        switch store.hermesConfigSummary.configType {
        case .readOnly:
            return .green
        case .askPerTask:
            return .orange
        case .alwaysAllow:
            return .red
        case .custom:
            return .secondary
        case .unavailable:
            return .orange
        }
    }
}
