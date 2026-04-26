import AppKit
import SwiftUI

@MainActor
final class AmbientMissionPanelController {
    private let panelSize = NSSize(width: 440, height: 286)
    private var window: AmbientMissionPanelWindow?

    func show(store: AURAStore) {
        if window == nil {
            let panel = AmbientMissionPanelWindow(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            panel.contentViewController = NSHostingController(
                rootView: AmbientMissionPanelView(store: store) { [weak self] in
                    self?.hide()
                }
            )
            window = panel
            AURATelemetry.info(.ambientPanelCreated, category: .ui)
        }

        positionNearCursor()
        window?.orderFrontRegardless()
        window?.makeKey()
        AURATelemetry.info(
            .ambientPanelShown,
            category: .ui,
            fields: [
                .string("status", store.missionStatus.title),
                .bool("has_pending_approval", store.pendingApproval != nil)
            ]
        )
    }

    func hide() {
        let wasVisible = window?.isVisible == true
        window?.orderOut(nil)
        if wasVisible {
            AURATelemetry.info(.ambientPanelHidden, category: .ui)
        }
    }

    private func positionNearCursor() {
        guard let window else { return }

        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: cursor.x + 18, y: cursor.y - panelSize.height - 24)

        if origin.x + panelSize.width > visibleFrame.maxX {
            origin.x = cursor.x - panelSize.width - 18
        }

        if origin.y < visibleFrame.minY {
            origin.y = cursor.y + 28
        }

        origin.x = min(max(origin.x, visibleFrame.minX + 12), visibleFrame.maxX - panelSize.width - 12)
        origin.y = min(max(origin.y, visibleFrame.minY + 12), visibleFrame.maxY - panelSize.height - 12)

        window.setFrameOrigin(origin)
    }
}

private final class AmbientMissionPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct AmbientMissionPanelView: View {
    @ObservedObject var store: AURAStore
    let close: () -> Void

    @FocusState private var goalFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 11, height: 11)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AURA")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }

            if let approval = store.pendingApproval, store.missionStatus == .needsApproval {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Approval needed", systemImage: "hand.raised")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                    Text(approval.title)
                        .font(.callout)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.automationPolicy == .readOnly {
                        Text("Read Only blocks this. Change the global policy before continuing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 116, alignment: .topLeading)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack(alignment: .topLeading) {
                    if store.missionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Ask AURA to explain, research, fix, build, organize, or operate through Hermes...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $store.missionGoal)
                        .focused($goalFocused)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .frame(height: 92)
                        .padding(4)
                        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("aura.ambient.goalEditor")
                }
            }

            Label("Global policy: \(store.automationPolicy.title)", systemImage: store.automationPolicy.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.pendingApproval != nil && store.missionStatus == .needsApproval {
                HStack {
                    Button(role: .cancel) {
                        store.denyPendingApproval()
                        close()
                    } label: {
                        Label("Deny", systemImage: "xmark")
                    }

                    Spacer()

                    Button {
                        Task {
                            await store.approvePendingAction()
                            if store.missionStatus == .running {
                                close()
                            }
                        }
                    } label: {
                        Label("Approve & Continue", systemImage: "checkmark")
                    }
                    .disabled(!store.canApproveMission)
                }
            } else {
                HStack {
                    Button(role: .cancel) {
                        store.cancelMission()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .disabled(!store.canCancelMission)

                    Button {
                        Task {
                            await store.startMission()
                            if store.missionStatus == .running {
                                close()
                            }
                        }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!store.canStartMission)
                    .accessibilityIdentifier("aura.ambient.start")
                }
            }
        }
        .padding(16)
        .frame(width: 440, height: 286)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .onAppear {
            goalFocused = true
        }
    }

    private var statusText: String {
        if store.isRunningCuaOnboarding {
            return "Checking CUA setup"
        }

        if store.isShortcutPulseActive {
            return "Shortcut active"
        }

        return store.missionStatus.title
    }

    private var statusColor: Color {
        if store.isRunningCuaOnboarding {
            return .orange
        }

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
}
