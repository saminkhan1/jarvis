import AppKit
import SwiftUI

struct CursorSurfaceView: View {
    @ObservedObject var store: AURAStore
    @ObservedObject var sessionManager: MissionSessionManager
    @ObservedObject var presentation: CursorSurfacePresentation
    let minimizeSurface: () -> Void

    @FocusState private var goalFocused: Bool

    var body: some View {
        ZStack {
            surfaceBackground

            if presentation.isComposerOpen {
                composerContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                compactContent
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .frame(width: width, height: height)
        .animation(.snappy(duration: 0.2), value: presentation.isComposerOpen)
        .onAppear { focusGoalIfNeeded() }
        .onChange(of: presentation.isComposerOpen) { _, isOpen in
            if isOpen {
                focusGoalIfNeeded()
            } else {
                goalFocused = false
            }
        }
    }

    private var expandedWidth: CGFloat { 260 }

    private var width: CGFloat {
        presentation.isComposerOpen ? expandedWidth : presentation.compactPanelSize.width
    }

    private var height: CGFloat {
        presentation.isComposerOpen ? expandedHeight : presentation.compactPanelSize.height
    }

    private var expandedHeight: CGFloat {
        if sessionManager.selectedSession != nil {
            return 226
        }

        let hasSessions = !sessionManager.sessions.isEmpty
        if store.inputMode == .voice {
            if store.voiceInputState == .ready {
                return hasSessions ? 216 : 184
            }
            return hasSessions ? 144 : 112
        }

        return hasSessions ? 176 : 144
    }

    private var surfaceBackground: some View {
        RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.card, style: .continuous)
            .fill(AURAVisualStyle.Colors.surface1.opacity(0.96))
            .overlay {
                RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [statusColor.opacity(0.14), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.card, style: .continuous)
                    .strokeBorder(AURAVisualStyle.Colors.border.opacity(0.5), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private var compactContent: some View {
        HStack(spacing: 8) {
            buddyMark

            Text(compactTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AURAVisualStyle.Colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var composerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            bubbleHeader

            if !sessionManager.sessions.isEmpty {
                sessionStrip
            }

            if let selectedSession = sessionManager.selectedSession {
                sessionOutputBody(session: selectedSession)
            } else {
                inputBody
            }

            actionZone
        }
    }

    private var sessionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    sessionManager.selectComposer()
                    focusGoalIfNeeded()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(sessionManager.selectedSession == nil ? AURAVisualStyle.Colors.accent : AURAVisualStyle.Colors.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(sessionManager.selectedSession == nil ? 0.12 : 0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New request")

                ForEach(sessionManager.sessions) { session in
                    SessionPill(session: session, isSelected: session.id == sessionManager.selectedSessionID)
                        .onTapGesture {
                            sessionManager.selectSession(session.id)
                            goalFocused = false
                        }
                }
            }
            .frame(height: 24)
        }
    }

    private var bubbleHeader: some View {
        HStack(spacing: 8) {
            buddyMark

            Text("AURA")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AURAVisualStyle.Colors.textPrimary)

            Text(headerStatusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AURAVisualStyle.Colors.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: minimizeSurface) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AURAVisualStyle.Colors.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Minimize AURA")
        }
    }

    private var buddyMark: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(statusColor.opacity(0.18))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(statusColor)
                        .rotationEffect(.degrees(-12))
                }
                .shadow(color: statusColor.opacity(isActiveVisualState ? 0.45 : 0.24), radius: isActiveVisualState ? 7 : 4, x: 0, y: 0)

            statusDot
                .offset(x: 1, y: 1)
        }
        .accessibilityHidden(true)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
            .shadow(color: statusColor.opacity(0.55), radius: isActiveVisualState ? 5 : 3, x: 0, y: 0)
    }

    @ViewBuilder
    private var inputBody: some View {
        switch store.inputMode {
        case .text:
            textInputBody
        case .voice:
            voiceInputBody
        }
    }

    private var textInputBody: some View {
        ZStack(alignment: .topLeading) {
            if store.missionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Ask anything…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AURAVisualStyle.Colors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
            }

            TextEditor(text: $store.missionGoal)
                .focused($goalFocused)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AURAVisualStyle.Colors.textPrimary)
                .frame(height: 64)
                .padding(3)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AURAVisualStyle.Colors.border.opacity(0.5), lineWidth: 0.7)
                )
                .accessibilityIdentifier("aura.cursor.goalEditor")
        }
    }

    private var voiceInputBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(voiceBodyCopy)
                .font(.system(size: 12, weight: store.voiceInputState == .failed ? .medium : .semibold))
                .foregroundStyle(voiceCopyColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if store.voiceInputState == .recording {
                HStack(spacing: 8) {
                    VoiceLevelMeter(level: store.voiceInputLevel, isActive: store.voiceInputState == .recording)

                    Text(formatVoiceDuration(store.voiceInputDuration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AURAVisualStyle.Colors.textTertiary)
                }
            }

            if store.voiceInputState == .ready {
                TextEditor(text: $store.missionGoal)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AURAVisualStyle.Colors.textPrimary)
                    .frame(height: 70)
                    .padding(5)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AURAVisualStyle.Colors.border.opacity(0.5), lineWidth: 0.7)
                    )
                    .accessibilityIdentifier("aura.cursor.voiceTranscriptEditor")
            }
        }
    }

    private var actionZone: some View {
        HStack(spacing: 7) {
            if store.inputMode == .text && sessionManager.selectedSession == nil {
                Text("⌘↩")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AURAVisualStyle.Colors.textTertiary)
            }

            Spacer(minLength: 0)

            if let selectedSession = sessionManager.selectedSession {
                Button {
                    sessionManager.selectComposer()
                    focusGoalIfNeeded()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(AURASecondaryButtonStyle(compact: true))

                switch selectedSession.status {
                case .running:
                    Button("Cancel") {
                        sessionManager.cancelSession(selectedSession.id)
                    }
                    .buttonStyle(AURAPrimaryButtonStyle(compact: true))
                case .completed, .failed, .cancelled:
                    Button("Done") {
                        sessionManager.removeSession(selectedSession.id)
                    }
                    .buttonStyle(AURAPrimaryButtonStyle(compact: true))
                case .idle:
                    EmptyView()
                }
            } else {
                idleActionButtons
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private var idleActionButtons: some View {
        switch store.inputMode {
        case .text:
            if shouldShowTextStartButton {
                Button("Start") {
                    Task { await store.startMission() }
                }
                .buttonStyle(AURAPrimaryButtonStyle(compact: true))
                .keyboardShortcut(.return, modifiers: [.command])
            }
        case .voice:
            voiceFooterActions
        }
    }

    @ViewBuilder
    private var voiceFooterActions: some View {
        switch store.voiceInputState {
        case .recording:
            Button("Retry") {
                Task { await store.redoVoiceInput() }
            }
            .buttonStyle(AURASecondaryButtonStyle(compact: true))

            Button("Stop") {
                Task { await store.toggleVoiceInput() }
            }
            .buttonStyle(AURAPrimaryButtonStyle(compact: true))
        case .ready:
            Button("Retry") {
                Task { await store.redoVoiceInput() }
            }
            .buttonStyle(AURASecondaryButtonStyle(compact: true))

            Button("Send") {
                Task { await store.startMission() }
            }
            .buttonStyle(AURAPrimaryButtonStyle(compact: true))
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!store.canStartMission)
        case .failed:
            Button("Retry") {
                Task { await store.redoVoiceInput() }
            }
            .buttonStyle(AURAPrimaryButtonStyle(compact: true))
        case .idle, .requestingPermission, .transcribing:
            EmptyView()
        }
    }

    private func sessionOutputBody(session: MissionSession) -> some View {
        outputBody(body: sessionBody(for: session))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outputBody(body: String) -> some View {
        ScrollView {
            Text(body)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AURAVisualStyle.Colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: 100)
    }

    private var shouldShowTextStartButton: Bool {
        store.inputMode == .text
            && store.canStartMission
    }

    private func runningFooterText(for session: MissionSession, now: Date = Date()) -> String {
        guard let startedAt = session.startedAt else {
            return "On it."
        }

        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        let formatted = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        return "On it · \(formatted)"
    }

    private var compactTitle: String {
        if store.isShortcutPulseActive { return "Listening" }
        if store.inputMode == .voice && !sessionManager.hasActiveSessions { return headerStatusText }
        return "AURA · \(headerStatusText)"
    }

    private var statusColor: Color {
        if store.isShortcutPulseActive {
            return AURAVisualStyle.Colors.success
        }

        if let selectedSession = sessionManager.selectedSession {
            return statusColor(for: selectedSession.status)
        }

        if sessionManager.hasActiveSessions {
            return AURAVisualStyle.Colors.warning
        }

        if let latestSession = sessionManager.latestSession, latestSession.isFinished {
            return statusColor(for: latestSession.status)
        }

        return store.inputMode == .voice ? voiceAccentColor : AURAVisualStyle.Colors.accent
    }

    private var isActiveVisualState: Bool {
        store.isShortcutPulseActive || store.voiceInputState == .recording || sessionManager.hasActiveSessions
    }

    private var headerStatusText: String {
        if store.isRunningCuaOnboarding {
            return "Checking setup"
        }

        if store.isShortcutPulseActive {
            return "Listening"
        }

        if let selectedSession = sessionManager.selectedSession {
            return statusText(for: selectedSession.status)
        }

        let activeCount = sessionManager.activeSessions.count
        if activeCount > 0 {
            return activeCount == 1 ? "1 working" : "\(activeCount) working"
        }

        if store.inputMode == .voice {
            switch store.voiceInputState {
            case .recording:
                return "Listening"
            case .transcribing:
                return "Processing"
            case .failed:
                return "Try again"
            case .ready:
                return "Ready"
            case .requestingPermission:
                return "Permission"
            case .idle:
                return "Ready"
            }
        }

        return sessionManager.latestSession.map { statusText(for: $0.status) } ?? "Ready"
    }

    private var voiceBodyCopy: String {
        switch store.voiceInputState {
        case .recording:
            return "I'm listening."
        case .transcribing:
            return "Processing…"
        case .failed:
            if store.voiceInputMessage.localizedCaseInsensitiveContains("speech")
                || store.voiceInputMessage.localizedCaseInsensitiveContains("recording") {
                return "Didn't catch that — try again?"
            }
            return store.voiceInputMessage.isEmpty ? "Didn't catch that — try again?" : store.voiceInputMessage
        case .ready:
            return "Looks good?"
        case .requestingPermission:
            return "Waiting for microphone permission…"
        case .idle:
            return "Say what you need."
        }
    }

    private var voiceCopyColor: Color {
        store.voiceInputState == .failed ? AURAVisualStyle.Colors.textSecondary : voiceAccentColor
    }

    private func focusGoalIfNeeded() {
        guard presentation.isComposerOpen,
              store.inputMode == .text,
              sessionManager.selectedSession == nil else { return }
        DispatchQueue.main.async {
            goalFocused = true
        }
    }

    private func sessionBody(for session: MissionSession) -> String {
        let trimmedOutput = session.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOutput.isEmpty {
            return session.output
        }

        switch session.status {
        case .running:
            return runningFooterText(for: session)
        case .completed:
            return "Done."
        case .failed:
            return "Something got stuck. Try again?"
        case .cancelled:
            return "Cancelled."
        case .idle:
            return "Queued."
        }
    }

    private func statusText(for status: MissionStatus) -> String {
        switch status {
        case .idle:
            return "Ready"
        case .running:
            return "Working"
        case .completed:
            return "Done"
        case .failed:
            return "Try again"
        case .cancelled:
            return "Cancelled"
        }
    }

    private func statusColor(for status: MissionStatus) -> Color {
        switch status {
        case .idle:
            return AURAVisualStyle.Colors.accent
        case .running:
            return AURAVisualStyle.Colors.warning
        case .completed:
            return AURAVisualStyle.Colors.success
        case .failed:
            return AURAVisualStyle.Colors.warning
        case .cancelled:
            return AURAVisualStyle.Colors.textTertiary
        }
    }

    private var voiceAccentColor: Color {
        switch store.voiceInputState {
        case .failed:
            return AURAVisualStyle.Colors.warning
        case .recording:
            return AURAVisualStyle.Colors.success
        case .transcribing:
            return AURAVisualStyle.Colors.warning
        case .ready:
            return AURAVisualStyle.Colors.accent
        case .idle, .requestingPermission:
            return AURAVisualStyle.Colors.accent
        }
    }

    private func formatVoiceDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SessionPill: View {
    @ObservedObject var session: MissionSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(session.displayTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AURAVisualStyle.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isSelected ? statusColor.opacity(0.18) : Color.white.opacity(0.06))
        )
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? statusColor.opacity(0.32) : Color.clear, lineWidth: 0.75)
        )
        .accessibilityLabel("\(session.displayTitle), \(session.status.title)")
    }

    private var statusColor: Color {
        switch session.status {
        case .idle:
            return AURAVisualStyle.Colors.textTertiary
        case .running:
            return AURAVisualStyle.Colors.warning
        case .completed:
            return AURAVisualStyle.Colors.success
        case .failed:
            return AURAVisualStyle.Colors.warning
        case .cancelled:
            return AURAVisualStyle.Colors.textTertiary
        }
    }
}

private struct VoiceLevelMeter: View {
    let level: Double
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<8, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
        .frame(height: 16, alignment: .center)
        .animation(.snappy(duration: 0.12), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        CGFloat(5 + ((index % 4) * 3))
    }

    private func barColor(for index: Int) -> Color {
        guard isActive else { return AURAVisualStyle.Colors.textTertiary.opacity(0.18) }
        let threshold = Double(index + 1) / 8
        return level >= threshold ? AURAVisualStyle.Colors.success : AURAVisualStyle.Colors.textTertiary.opacity(0.32)
    }
}
