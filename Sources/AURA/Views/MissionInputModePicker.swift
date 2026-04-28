import SwiftUI

struct MissionInputModePicker: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if MissionInputMode.allCases.count > 1 {
                Picker("Mission Input", selection: $store.inputMode) {
                    ForEach(MissionInputMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Label(store.inputMode.title, systemImage: store.inputMode.systemImage)
                    .font(.callout.weight(.medium))
            }

            Label(store.inputMode.summary, systemImage: store.inputMode.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
