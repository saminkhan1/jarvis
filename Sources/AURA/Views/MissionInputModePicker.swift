import SwiftUI

struct MissionInputModePicker: View {
    @ObservedObject var store: AURAStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mission Input", selection: $store.inputMode) {
                ForEach(MissionInputMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Label(store.inputMode.summary, systemImage: store.inputMode.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
