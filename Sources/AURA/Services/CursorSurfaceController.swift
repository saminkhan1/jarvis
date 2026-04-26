import AppKit
import SwiftUI

@MainActor
final class CursorSurfaceController {
    private static let compactPanelSize = NSSize(width: 360, height: 154)
    private static let composerPanelSize = NSSize(width: 440, height: 286)

    private var window: CursorSurfaceWindow?
    private var timer: Timer?
    private var lastOrderFrontAt = Date.distantPast
    private var isVisible = false

    let presentation = CursorSurfacePresentation()

    func setVisible(_ isVisible: Bool, store: AURAStore) {
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
            window?.orderFrontRegardless()
            startTracking()
            return
        }

        presentation.isComposerOpen = false
        stopTracking()
        window?.orderOut(nil)
        self.isVisible = false
    }

    func presentComposer(using store: AURAStore) {
        presentation.isComposerOpen = true
        setVisible(true, store: store)
        updateWindowLayout(animate: true)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AURATelemetry.info(.ambientPanelShown, category: .ui)
    }

    func collapseToCompact() {
        guard presentation.isComposerOpen else { return }
        presentation.isComposerOpen = false
        updateWindowLayout(animate: true)
        window?.orderFrontRegardless()
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
        guard window == nil else { return }

        let panel = CursorSurfaceWindow(
            contentRect: NSRect(origin: .zero, size: Self.composerPanelSize),
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
                presentation: presentation,
                closeComposer: { [weak self] in
                    self?.collapseToCompact()
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

    private func updateWindowLayout(animate: Bool) {
        guard let window else { return }
        let size = panelSize
        let origin = panelOrigin(for: size)
        let frame = NSRect(origin: origin, size: size)
        window.ignoresMouseEvents = !presentation.isComposerOpen
        window.setFrame(frame, display: true, animate: animate)
    }

    private func positionNearCursor() {
        guard let window else { return }

        let size = panelSize
        let origin = panelOrigin(for: size)
        window.ignoresMouseEvents = !presentation.isComposerOpen
        window.setFrame(NSRect(origin: origin, size: size), display: true)

        let now = Date()
        if now.timeIntervalSince(lastOrderFrontAt) > 1 {
            window.orderFrontRegardless()
            lastOrderFrontAt = now
        }
    }

    private var panelSize: NSSize {
        presentation.isComposerOpen ? Self.composerPanelSize : Self.compactPanelSize
    }

    private func panelOrigin(for size: NSSize) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

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
}

@MainActor
final class CursorSurfacePresentation: ObservableObject {
    @Published var isComposerOpen = false
}

private final class CursorSurfaceWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
