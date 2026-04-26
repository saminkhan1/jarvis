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
        presentation.isComposerOpen ? 440 : 360
    }

    private var height: CGFloat {
        presentation.isComposerOpen ? 286 : 154
    }

    private var compactContent: some View {
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

            Text(compactMessage)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(compactHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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

            if shouldShowApproval {
                approvalCard
            } else if store.missionStatus == .running {
                runningCard
            } else {
                promptCard
            }

            HStack(alignment: .center, spacing: 10) {
                Label("Tools: \(store.hermesToolSurfaceTitle)", systemImage: store.hermesToolSurfaceSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if store.missionStatus == .running {
                    Button("Collapse", action: closeComposer)
                        .buttonStyle(.bordered)
                } else if shouldShowApproval {
                    Button("Deny") {
                        store.denyPendingApproval()
                        closeComposer()
                    }
                    .buttonStyle(.bordered)

                    Button("Approve & Continue") {
                        Task { await store.approvePendingAction() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canApproveMission)
                } else {
                    Button("Cancel") {
                        store.cancelMission()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canCancelMission)

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

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if store.missionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Ask AURA to explain, research, fix, build, organize, or operate through Hermes...")
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
                Text("Command-Return starts Hermes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
        }
    }

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hermes is running", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundStyle(.blue)

            Text(runningMessage)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Text("The composer collapses while Hermes works.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Approval needed", systemImage: "hand.raised")
                .font(.headline)
                .foregroundStyle(.orange)

            if let approval = store.pendingApproval {
                Text(approval.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(approval.risk) · \(approval.scope)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Hermes config controls whether the approved action is available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var shouldShowApproval: Bool {
        store.pendingApproval != nil && store.missionStatus == .needsApproval
    }

    private var statusColor: Color {
        if store.isShortcutPulseActive {
            return .green
        }

        switch store.missionStatus {
        case .idle:
            return .blue
        case .needsApproval:
            return .orange
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

    private var compactMessage: String {
        CursorSurfaceText.message(
            for: store.missionStatus,
            isShortcutActive: store.isShortcutPulseActive,
            missionOutput: store.missionOutput,
            pendingApprovalTitle: store.pendingApproval?.title
        )
    }

    private var compactHint: String {
        CursorSurfaceText.actionHint(
            for: store.missionStatus,
            isShortcutActive: store.isShortcutPulseActive,
            missionOutput: store.missionOutput,
            hermesToolSurfaceTitle: store.hermesToolSurfaceTitle
        )
    }

    private var runningMessage: String {
        CursorSurfaceText.latestMeaningfulLine(in: store.missionOutput) ?? "Working on it."
    }

    private func focusGoalIfNeeded() {
        guard presentation.isComposerOpen, shouldShowApproval == false, store.missionStatus != .running else { return }
        DispatchQueue.main.async {
            goalFocused = true
        }
    }
}

private enum CursorSurfaceText {
    static func message(
        for status: MissionStatus,
        isShortcutActive: Bool,
        missionOutput: String,
        pendingApprovalTitle: String?
    ) -> String {
        if isShortcutActive {
            return "Ready for a request."
        }

        if status == .needsApproval, let pendingApprovalTitle, !pendingApprovalTitle.isEmpty {
            return compact(pendingApprovalTitle)
        }

        switch status {
        case .idle:
            return "Ask me to inspect, explain, research, or operate."
        case .running:
            return compact(latestMeaningfulLine(in: missionOutput) ?? "Working on it.")
        case .needsApproval:
            return "I need approval before continuing."
        case .completed:
            return compact(finalSummary(from: missionOutput) ?? "Done.")
        case .failed:
            return compact(finalSummary(from: missionOutput) ?? "Something failed.")
        case .cancelled:
            return "Mission cancelled."
        }
    }

    static func actionHint(
        for status: MissionStatus,
        isShortcutActive: Bool,
        missionOutput: String,
        hermesToolSurfaceTitle: String
    ) -> String {
        if isShortcutActive {
            return "Type in the composer, then press Command-Return."
        }

        switch status {
        case .idle:
            return "Control-Option-Command-A opens the composer. Tools: \(hermesToolSurfaceTitle)."
        case .running:
            return "I will update here while Hermes works."
        case .needsApproval:
            return "Open the composer to approve or deny."
        case .completed:
            if let recommendedAction = recommendedAction(from: missionOutput) {
                return compact("Next: \(recommendedAction)", limit: 92)
            }
            return "Open the composer to start another request."
        case .failed:
            return "Open the composer or dashboard for details."
        case .cancelled:
            return "Open the composer to start again."
        }
    }

    static func latestMeaningfulLine(in output: String) -> String? {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .reversed()
            .first { line in
                !line.isEmpty
                    && !line.lowercased().hasPrefix("session_id:")
                    && !line.hasPrefix("[")
            }
    }

    static func finalSummary(from output: String) -> String? {
        let lines = cleanedLines(from: output)

        guard !lines.isEmpty else { return nil }

        if let summary = fieldValue(named: ["final summary", "summary"], in: lines) {
            return summary
        }

        if let outcome = fieldValue(named: ["outcome", "answer", "result", "summary"], in: lines) {
            return outcome
        }

        return lines.first { line in
            let stripped = stripListMarker(line)
            let lower = stripped.lowercased()
            return !isMetadataLine(lower)
                && !lower.hasSuffix(":")
                && lower.contains(".")
        } ?? lines.last.map(stripListMarker)
    }

    static func recommendedAction(from output: String) -> String? {
        fieldValue(
            named: ["recommended next action", "recommended action", "next action"],
            in: cleanedLines(from: output)
        )
    }

    private static func cleanedLines(from output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                return !isMetadataLine(stripListMarker(line).lowercased())
            }
    }

    private static func fieldValue(named names: [String], in lines: [String]) -> String? {
        for line in lines {
            let stripped = stripListMarker(line)
            let lower = stripped.lowercased()

            for name in names {
                let prefix = "\(name.lowercased()):"
                guard lower.hasPrefix(prefix) else { continue }

                let start = stripped.index(stripped.startIndex, offsetBy: prefix.count)
                let value = stripped[start...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }

        return nil
    }

    private static func stripListMarker(_ line: String) -> String {
        var result = line.trimmingCharacters(in: .whitespacesAndNewlines)

        while let first = result.first, first == "-" || first == "*" || first == "•" {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    private static func isMetadataLine(_ lowercasedLine: String) -> Bool {
        lowercasedLine.hasPrefix("session_id:")
            || lowercasedLine.hasPrefix("status:")
            || lowercasedLine == "final packet"
            || lowercasedLine.hasPrefix("artifacts/")
            || lowercasedLine.hasPrefix("artifacts:")
            || lowercasedLine.hasPrefix("sources:")
            || lowercasedLine.hasPrefix("blocked approvals:")
    }

    private static func compact(_ text: String, limit: Int = 210) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard normalized.count > limit else { return normalized }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: max(0, limit - 3))
        return String(normalized[..<endIndex]) + "..."
    }
}
