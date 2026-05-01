import Foundation
import SwiftUI

struct CursorSurfaceView: View {
    private static let bubbleWidth: CGFloat = 340
    private static let outputViewportWidth: CGFloat = 312
    private static let minimumSessionBubbleHeight: CGFloat = 82
    private static let sessionChromeHeight: CGFloat = 50
    private static let outputLineHeight: CGFloat = 19
    private static let maximumOutputViewportHeight: CGFloat = 228

    @ObservedObject var store: AURAStore
    @ObservedObject var sessionManager: MissionSessionManager
    let minimizeSurface: () -> Void

    @FocusState private var goalFocused: Bool

    var body: some View {
        Group {
            if let session = displaySession {
                sessionBubble(session)
            } else {
                switch store.inputMode {
                case .text:
                    textInputBubble
                case .voice:
                    voiceMessageBubble
                }
            }
        }
        .frame(maxWidth: Self.bubbleWidth, alignment: .topLeading)
        .onAppear {
            focusTextInputIfNeeded()
        }
        .onChange(of: store.inputMode) { _, _ in
            focusTextInputIfNeeded()
        }
        .onExitCommand(perform: minimizeSurface)
    }

    private var displaySession: MissionSession? {
        if let selectedSession = sessionManager.selectedSession {
            return selectedSession
        }

        if let activeSession = sessionManager.activeSessions.first {
            return activeSession
        }

        guard let latestSession = sessionManager.latestSession,
              latestSession.isFinished else {
            return nil
        }

        return latestSession
    }

    private var textInputBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if store.missionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(ClickyBubbleStyle.textTertiary)
                        .lineSpacing(3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                TextEditor(text: $store.missionGoal)
                    .focused($goalFocused)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(ClickyBubbleStyle.textPrimary)
                    .lineSpacing(3)
                    .frame(width: 312, height: 82, alignment: .topLeading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.clear)
                    .accessibilityIdentifier("aura.cursor.goalEditor")
            }

            HStack(spacing: 8) {
                Text("Command-Return")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ClickyBubbleStyle.textTertiary)

                Spacer(minLength: 0)

                Button(action: submitTextInput) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(store.canStartMission ? ClickyBubbleStyle.accent : ClickyBubbleStyle.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.plain)
                .disabled(!store.canStartMission)
                .accessibilityLabel("Send request")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 9)
        }
        .frame(width: 340, height: 126, alignment: .topLeading)
        .background(ClickyBubbleBackground())
    }

    private var voiceMessageBubble: some View {
        responseBubble(text: store.voiceInputMessage.isEmpty ? "..." : store.voiceInputMessage)
    }

    private func sessionBubble(_ session: MissionSession) -> some View {
        let output = outputText(for: session)
        let outputHeight = outputViewportHeight(for: output)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor(for: session.status))
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor(for: session.status).opacity(0.6), radius: 4)

                Text(statusTitle(for: session))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ClickyBubbleStyle.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if session.status == .running {
                    Button {
                        sessionManager.cancelSession(session.id)
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ClickyBubbleStyle.textPrimary)
                            .frame(width: 22, height: 22)
                            .background(ClickyBubbleStyle.danger.opacity(0.28), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel running request")
                }
            }
            .frame(width: Self.outputViewportWidth, alignment: .leading)

            ScrollView(.vertical) {
                Text(output)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(ClickyBubbleStyle.textPrimary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
            .frame(width: Self.outputViewportWidth, height: outputHeight, alignment: .topLeading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(
            width: Self.bubbleWidth,
            height: max(outputHeight + Self.sessionChromeHeight, Self.minimumSessionBubbleHeight),
            alignment: .topLeading
        )
        .background(ClickyBubbleBackground())
    }

    private func responseBubble(text: String) -> some View {
        Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "..." : text)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(ClickyBubbleStyle.textPrimary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ClickyBubbleBackground())
    }

    private func outputText(for session: MissionSession) -> String {
        let trimmedOutput = session.output.trimmingCharacters(in: .whitespacesAndNewlines)

        if session.status == .running {
            let runningLine = "Working on \"\(session.displayTitle)\"..."
            guard !trimmedOutput.isEmpty,
                  trimmedOutput != "Starting Hermes..." else {
                return runningLine
            }
            return "\(runningLine)\n\(trimmedOutput)"
        }

        if !trimmedOutput.isEmpty {
            return session.output
        }

        switch session.status {
        case .completed:
            return "Done."
        case .failed:
            return "Something got stuck. Try again?"
        case .cancelled:
            return "Cancelled."
        case .idle:
            return "..."
        case .running:
            return "Working..."
        }
    }

    private func outputViewportHeight(for output: String) -> CGFloat {
        let estimatedLines = estimatedOutputLineCount(in: output)
        return min(
            max(CGFloat(estimatedLines) * Self.outputLineHeight, Self.outputLineHeight),
            Self.maximumOutputViewportHeight
        )
    }

    private func estimatedOutputLineCount(in output: String) -> Int {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1 }

        return trimmed
            .components(separatedBy: .newlines)
            .reduce(0) { lineCount, line in
                lineCount + max(Int(ceil(Double(max(line.count, 1)) / 42.0)), 1)
            }
    }

    private func statusTitle(for session: MissionSession) -> String {
        switch session.status {
        case .idle:
            return "Queued"
        case .running:
            return "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Needs attention"
        case .cancelled:
            return "Cancelled"
        }
    }

    private func statusColor(for status: MissionStatus) -> Color {
        switch status {
        case .idle:
            return ClickyBubbleStyle.textTertiary
        case .running:
            return ClickyBubbleStyle.accent
        case .completed:
            return ClickyBubbleStyle.success
        case .failed:
            return ClickyBubbleStyle.danger
        case .cancelled:
            return ClickyBubbleStyle.textTertiary
        }
    }

    private func submitTextInput() {
        guard store.canStartMission else { return }
        Task { await store.startMission() }
    }

    private func focusTextInputIfNeeded() {
        guard store.inputMode == .text,
              displaySession == nil else { return }

        DispatchQueue.main.async {
            goalFocused = true
        }
    }
}

private enum ClickyBubbleStyle {
    static let surface1 = Color(hex: "#171918")
    static let borderSubtle = Color(hex: "#373B39")
    static let textPrimary = Color(hex: "#ECEEED")
    static let textSecondary = Color(hex: "#A9B3AF")
    static let textTertiary = Color(hex: "#6B736F")
    static let accent = Color(hex: "#3380FF")
    static let success = Color(hex: "#34D399")
    static let danger = Color(hex: "#F87171")
}

private struct ClickyBubbleBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(ClickyBubbleStyle.surface1.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(ClickyBubbleStyle.borderSubtle.opacity(0.5), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 8)
    }
}
