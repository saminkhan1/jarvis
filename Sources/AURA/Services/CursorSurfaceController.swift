import AppKit
import SwiftUI

enum CursorSurfaceSizing {
    static let defaultCompactPanelSize = NSSize(width: 180, height: 46)

    @MainActor
    static func compactPanelSize(for _: AURAStore?, visibleFrame _: NSRect) -> NSSize {
        defaultCompactPanelSize
    }
}

@MainActor
final class CursorSurfaceController {
    private static let textComposerPanelSize = NSSize(width: 260, height: 144)
    private static let textComposerWithSessionsPanelSize = NSSize(width: 260, height: 176)
    private static let voiceComposerPanelSize = NSSize(width: 260, height: 112)
    private static let voiceComposerWithSessionsPanelSize = NSSize(width: 260, height: 144)
    private static let voiceReadyComposerPanelSize = NSSize(width: 260, height: 184)
    private static let voiceReadyWithSessionsComposerPanelSize = NSSize(width: 260, height: 216)
    private static let outputComposerPanelSize = NSSize(width: 260, height: 226)

    private var window: CursorSurfaceWindow?
    private weak var store: AURAStore?
    private var timer: Timer?
    private var lastOrderFrontAt = Date.distantPast
    private var isVisible = false

    let presentation = CursorSurfacePresentation()

    func setVisible(_ isVisible: Bool, store: AURAStore) {
        self.store = store

        if self.isVisible != isVisible {
            AURATelemetry.info(
                .cursorIndicatorVisibilityChanged,
                category: .ui,
                fields: [.bool("visible", isVisible)]
            )
            self.isVisible = isVisible
        }

        if isVisible {
            ensureWindow(store: store)
            updateWindowLayout(animate: false)
            updateCompactTracking()
            window?.orderFrontRegardless()
            return
        }

        presentation.isComposerOpen = false
        stopTracking()
        window?.orderOut(nil)
        self.isVisible = false
    }

    func presentComposer(using store: AURAStore) {
        self.store = store
        let wasComposerOpen = presentation.isComposerOpen
        presentation.isComposerOpen = true
        ensureWindow(store: store)
        updateWindowLayout(animate: !wasComposerOpen)
        updateCompactTracking()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.isVisible = true
        AURATelemetry.info(.ambientPanelShown, category: .ui)
    }

    func collapseToCompact() {
        guard presentation.isComposerOpen else { return }
        presentation.isComposerOpen = false
        updateWindowLayout(animate: true)
        window?.orderFrontRegardless()
        updateCompactTracking()
    }

    func hide() {
        let wasVisible = window?.isVisible == true
        presentation.isComposerOpen = false
        stopTracking()
        window?.orderOut(nil)
        self.isVisible = false
        if wasVisible {
            AURATelemetry.info(.ambientPanelHidden, category: .ui)
        }
    }

    private func ensureWindow(store: AURAStore) {
        self.store = store
        guard window == nil else { return }

        let panel = CursorSurfaceWindow(
            contentRect: NSRect(origin: .zero, size: Self.textComposerPanelSize),
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
            rootView: CursorSurfaceView(
                store: store,
                sessionManager: store.sessionManager,
                presentation: presentation,
                minimizeSurface: { [weak self] in
                    self?.store?.minimizeAmbientSurface()
                }
            )
        )
        window = panel
        AURATelemetry.info(.ambientPanelCreated, category: .ui)
    }

    private func startTracking() {
        guard timer == nil else { return }
        positionNearCursor()
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.positionNearCursor()
            }
        }
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCompactTracking() {
        guard !presentation.isComposerOpen else {
            stopTracking()
            return
        }

        if shouldTrackCompactPanel {
            startTracking()
        } else {
            stopTracking()
        }
    }

    private func updateWindowLayout(animate: Bool) {
        guard let window else { return }
        let size = panelSize
        let origin = panelOrigin(for: size)
        let frame = NSRect(origin: origin, size: size)
        window.ignoresMouseEvents = shouldIgnoreMouseEvents
        window.setFrame(frame, display: true, animate: animate)
    }

    private func positionNearCursor() {
        guard let window else { return }
        guard shouldTrackCompactPanel else {
            stopTracking()
            return
        }

        let size = panelSize
        let origin = panelOrigin(for: size)
        window.ignoresMouseEvents = shouldIgnoreMouseEvents
        window.setFrame(NSRect(origin: origin, size: size), display: true)

        let now = Date()
        if now.timeIntervalSince(lastOrderFrontAt) > 1 {
            window.orderFrontRegardless()
            lastOrderFrontAt = now
        }
    }

    private var panelSize: NSSize {
        if presentation.isComposerOpen {
            if store?.sessionManager.selectedSession != nil {
                return Self.outputComposerPanelSize
            }

            let hasSessions = store?.sessionManager.sessions.isEmpty == false
            if store?.inputMode == .voice {
                if store?.voiceInputState == .ready {
                    return hasSessions ? Self.voiceReadyWithSessionsComposerPanelSize : Self.voiceReadyComposerPanelSize
                }
                return hasSessions ? Self.voiceComposerWithSessionsPanelSize : Self.voiceComposerPanelSize
            }

            return hasSessions ? Self.textComposerWithSessionsPanelSize : Self.textComposerPanelSize
        }

        let size = CursorSurfaceSizing.compactPanelSize(for: store, visibleFrame: visibleFrameContainingCursor())
        if presentation.compactPanelSize != size {
            presentation.compactPanelSize = size
        }
        return size
    }

    private var shouldIgnoreMouseEvents: Bool {
        !presentation.isComposerOpen
    }

    private var shouldTrackCompactPanel: Bool {
        !presentation.isComposerOpen
    }

    private func panelOrigin(for size: NSSize) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        let visibleFrame = visibleFrameContainingCursor()

        var origin = NSPoint(x: cursor.x + 18, y: cursor.y - size.height - 24)

        if origin.x + size.width > visibleFrame.maxX {
            origin.x = cursor.x - size.width - 18
        }

        if origin.y < visibleFrame.minY {
            origin.y = cursor.y + 28
        }

        origin.x = min(max(origin.x, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
        origin.y = min(max(origin.y, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
        return origin
    }

    private func visibleFrameContainingCursor() -> NSRect {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

@MainActor
final class CursorSurfacePresentation: ObservableObject {
    @Published var isComposerOpen = false
    @Published var compactPanelSize = CursorSurfaceSizing.defaultCompactPanelSize
}

private final class CursorSurfaceWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
