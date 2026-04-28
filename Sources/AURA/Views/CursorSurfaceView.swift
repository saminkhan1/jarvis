import AppKit
import SwiftUI

struct CursorSurfaceView: View {
    @ObservedObject var store: AURAStore
    @ObservedObject var presentation: CursorSurfacePresentation
    let closeComposer: () -> Void

    @FocusState private var goalFocused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                statusColor.opacity(presentation.isComposerOpen ? 0.14 : 0.08),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(presentation.isComposerOpen ? 0.12 : 0.08), lineWidth: 1)

            if presentation.isComposerOpen {
                composerContent
                    .padding(16)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                compactContent
                    .padding(14)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .frame(width: width, height: height)
        .animation(.snappy(duration: 0.22), value: presentation.isComposerOpen)
        .onAppear {
            focusGoalIfNeeded()
        }
        .onChange(of: presentation.isComposerOpen) { _, isOpen in
            if isOpen {
                focusGoalIfNeeded()
            } else {
                goalFocused = false
            }
        }
    }

    private var width: CGFloat {
        presentation.isComposerOpen ? 440 : presentation.compactPanelSize.width
    }

    private var height: CGFloat {
        presentation.isComposerOpen ? (store.inputMode == .voice ? 326 : 286) : presentation.compactPanelSize.height
    }

    @ViewBuilder
    private var compactContent: some View {
        if usesMinimalCompactIndicator {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.3), radius: 5, x: 0, y: 0)

                Text(headerStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 11, height: 11)
                        .shadow(color: statusColor.opacity(0.3), radius: 5, x: 0, y: 0)

                    Text(headerStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)

                    Spacer(minLength: 0)

                    Text(store.hermesToolSurfaceTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }

                if shouldShowMissionOutput {
                    ScrollView {
                        Text(rawMissionOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text(compactStatusText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var composerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 11, height: 11)
                    .shadow(color: statusColor.opacity(0.3), radius: 5, x: 0, y: 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AURA")
                        .font(.headline)
                    Text(headerStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: closeComposer) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Collapse composer")
            }

            switch store.missionStatus {
            case .running:
                runningCard
            case .completed, .failed, .cancelled:
                resultCard
            case .idle:
                inputCard
            }

            HStack(alignment: .center, spacing: 10) {
                Label("Tools: \(store.hermesToolSurfaceTitle)", systemImage: store.hermesToolSurfaceSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                switch store.missionStatus {
                case .running:
                    Button("Collapse", action: closeComposer)
                        .buttonStyle(.bordered)

                    Button("Cancel") {
                        if store.canCancelVoiceInput {
                            store.cancelVoiceInput()
                        } else {
                            store.cancelMission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canCancelMission && !store.canCancelVoiceInput)
                case .completed, .failed, .cancelled:
                    Button("Done") {
                        store.dismissMissionResult()
                    }
                    .buttonStyle(.borderedProminent)
                case .idle:
                    Button("Start") {
                        Task { await store.startMission() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!store.canStartMission)
                }
            }
        }
    }

    @ViewBuilder
    private var inputCard: some View {
        switch store.inputMode {
        case .text:
            promptCard
        case .voice:
            voicePromptCard
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if store.missionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Ask Hermes to explain, research, fix, build, organize, or operate…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                }

                TextEditor(text: $store.missionGoal)
                    .focused($goalFocused)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .frame(height: 94)
                    .padding(4)
                    .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityIdentifier("aura.cursor.goalEditor")
            }

            HStack {
                Text("Command-Return sends this to Hermes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
        }
    }

    private var voicePromptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Button {
                    Task { await store.toggleVoiceInput() }
                } label: {
                    Image(systemName: voiceButtonImage)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(voiceAccentColor)
                        .frame(width: 62, height: 62)
                        .background(voiceAccentColor.opacity(0.12), in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(voiceAccentColor.opacity(0.28), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!store.canToggleVoiceInput)
                .accessibilityLabel(voiceButtonLabel)
                .accessibilityIdentifier("aura.cursor.voiceToggle")

                VStack(alignment: .leading, spacing: 7) {
                    Label(store.voiceInputState.title, systemImage: store.voiceInputState.systemImage)
                        .font(.headline)
                        .foregroundStyle(voiceAccentColor)

                    Text(store.voiceInputMessage)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        VoiceLevelMeter(level: store.voiceInputLevel, isActive: store.voiceInputState == .recording)

                        Text(formatVoiceDuration(store.voiceInputDuration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .opacity(store.voiceInputState == .recording ? 1 : 0)
                    }
                }

                Spacer(minLength: 0)

                Group {
                    if store.voiceInputState == .recording {
                        Button {
                            Task { await store.toggleVoiceInput() }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(width: 94, alignment: .trailing)
            }

            if !store.voiceInputTranscript.isEmpty {
                Text(store.voiceInputTranscript)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityIdentifier("aura.cursor.voiceTranscript")
            }

            HStack {
                Button {
                    store.clearVoiceInput()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(store.voiceInputState.isBusy && store.voiceInputState != .recording)

                Spacer(minLength: 0)

                Text(voiceFooterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(voiceAccentColor.opacity(0.14), lineWidth: 1)
        )
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(resultTitle, systemImage: resultIcon)
                .font(.headline)
                .foregroundStyle(resultColor)

            ScrollView {
                Text(resultBody)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: 96)
            .foregroundStyle(.primary)

            Text(resultFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(resultColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hermes is working", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundStyle(.blue)

            ScrollView {
                Text(hasMissionOutput ? rawMissionOutput : "Working on it.")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: 96)
            .foregroundStyle(.primary)

            Text("You can keep this open, collapse it, or cancel the run.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var usesMinimalCompactIndicator: Bool {
        guard !presentation.isComposerOpen, !shouldShowMissionOutput else { return false }
        switch store.missionStatus {
        case .idle, .running, .cancelled:
            return true
        case .completed, .failed:
            return false
        }
    }

    private var statusColor: Color {
        if store.isShortcutPulseActive {
            return .green
        }

        switch store.missionStatus {
        case .idle:
            return .blue
        case .running:
            return .purple
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        }
    }

    private var headerStatusText: String {
        if store.isRunningCuaOnboarding {
            return "Checking CUA setup"
        }

        if store.isShortcutPulseActive {
            return "Shortcut active"
        }

        return store.missionStatus.title
    }

    private var rawMissionOutput: String {
        store.missionOutput
    }

    private var hasMissionOutput: Bool {
        !rawMissionOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowMissionOutput: Bool {
        switch store.missionStatus {
        case .running, .completed, .failed:
            return hasMissionOutput
        case .idle, .cancelled:
            return false
        }
    }

    private var compactStatusText: String {
        if store.isShortcutPulseActive {
            return "Ready for a request."
        }

        switch store.missionStatus {
        case .idle:
            return "Ask Hermes to inspect, explain, research, or operate."
        case .running:
            return hasMissionOutput ? rawMissionOutput : "Working on it."
        case .completed, .failed:
            return rawMissionOutput
        case .cancelled:
            return "Run cancelled."
        }
    }

    private var resultTitle: String {
        switch store.missionStatus {
        case .completed:
            return "Hermes finished"
        case .failed:
            return "Hermes failed"
        case .cancelled:
            return "Run cancelled"
        case .idle, .running:
            return ""
        }
    }

    private var resultBody: String {
        if hasMissionOutput {
            return rawMissionOutput
        }

        switch store.missionStatus {
        case .completed:
            return "Hermes finished without returning output."
        case .failed:
            return "Hermes failed without returning output."
        case .cancelled:
            return "The run was cancelled before Hermes finished."
        case .idle, .running:
            return ""
        }
    }

    private var resultFooter: String {
        switch store.missionStatus {
        case .completed:
            return "Review the result, then click Done to return to the base state."
        case .failed:
            return "Review the error, then click Done to return to the base state."
        case .cancelled:
            return "Click Done to clear this run and continue your work."
        case .idle, .running:
            return ""
        }
    }

    private var resultIcon: String {
        switch store.missionStatus {
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        case .cancelled:
            return "stop.circle"
        case .idle, .running:
            return "circle"
        }
    }

    private var resultColor: Color {
        switch store.missionStatus {
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        case .idle, .running:
            return .secondary
        }
    }

    private func focusGoalIfNeeded() {
        guard presentation.isComposerOpen,
              store.inputMode == .text,
              store.missionStatus != .running else { return }
        DispatchQueue.main.async {
            goalFocused = true
        }
    }

    private var voiceButtonImage: String {
        switch store.voiceInputState {
        case .recording:
            return "stop.fill"
        case .transcribing:
            return "waveform"
        default:
            return "mic.fill"
        }
    }

    private var voiceButtonLabel: String {
        store.voiceInputState == .recording ? "Stop voice input" : "Start voice input"
    }

    private var voiceAccentColor: Color {
        switch store.voiceInputState {
        case .failed:
            return .red
        case .recording:
            return .green
        case .transcribing:
            return .blue
        case .ready:
            return .purple
        case .idle, .requestingPermission:
            return .accentColor
        }
    }

    private var voiceFooterText: String {
        switch store.voiceInputState {
        case .ready:
            return "AURA will send this transcript to Hermes."
        case .recording:
            return "Pause to stop automatically, or click Stop."
        case .transcribing:
            return "Transcribing with Hermes."
        case .failed:
            return "Clear this and try again."
        case .idle, .requestingPermission:
            return "Use the shortcut or mic button to start speaking."
        }
    }

    private func formatVoiceDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct VoiceLevelMeter: View {
    let level: Double
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(height: 24, alignment: .center)
        .animation(.snappy(duration: 0.12), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        CGFloat(8 + ((index % 6) * 3))
    }

    private func barColor(for index: Int) -> Color {
        guard isActive else { return Color.secondary.opacity(0.22) }
        let threshold = Double(index + 1) / 12
        return level >= threshold ? Color.green : Color.secondary.opacity(0.22)
    }
}
