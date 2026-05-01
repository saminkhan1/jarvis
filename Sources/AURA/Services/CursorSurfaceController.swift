import AppKit
import Carbon
import SwiftUI

@MainActor
final class CursorSurfaceController {
    private static let bubblePanelWidth: CGFloat = 340
    private static let textInputPanelSize = NSSize(width: bubblePanelWidth, height: 126)
    private static let voiceMessagePanelSize = NSSize(width: bubblePanelWidth, height: 64)
    private static let minimumSessionPanelHeight: CGFloat = 82
    private static let sessionChromeHeight: CGFloat = 50
    private static let outputLineHeight: CGFloat = 19
    private static let maximumOutputViewportHeight: CGFloat = 228

    private var window: CursorSurfaceWindow?
    private var overlayWindows: [CursorSurfaceOverlayWindow] = []
    private weak var store: AURAStore?
    private var escapeKeyMonitor: Any?
    private var bubbleAnchorTopLeft: NSPoint?
    private var bubbleAnchorVisibleFrame: NSRect?
    private var isVisible = false
    private var hasShownCursorOverlay = false

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

        guard isVisible else {
            hide()
            return
        }

        if presentation.isComposerOpen {
            ensureWindow(store: store)
            updateWindowLayout(animate: false)
            updateCursorOverlayVisibility(store: store)
        } else {
            resetBubbleAnchor()
            window?.orderOut(nil)
            showCursorOverlay(store: store)
        }
    }

    func presentComposer(using store: AURAStore) {
        self.store = store
        presentation.isComposerOpen = true
        resetBubbleAnchor()
        ensureWindow(store: store)
        startEscapeKeyMonitor()
        updateWindowLayout(animate: true)
        updateCursorOverlayVisibility(store: store)

        if shouldShowBubblePanel {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        isVisible = true
        AURATelemetry.info(.ambientPanelShown, category: .ui)
    }

    func closeBubblePanel() {
        guard presentation.isComposerOpen else { return }
        presentation.isComposerOpen = false
        stopEscapeKeyMonitor()
        resetBubbleAnchor()
        window?.orderOut(nil)
        if let store, isVisible {
            showCursorOverlay(store: store)
        }
    }

    func hide() {
        let wasVisible = window?.isVisible == true || !overlayWindows.isEmpty
        presentation.isComposerOpen = false
        stopEscapeKeyMonitor()
        resetBubbleAnchor()
        hideCursorOverlay()
        window?.orderOut(nil)
        isVisible = false
        if wasVisible {
            AURATelemetry.info(.ambientPanelHidden, category: .ui)
        }
    }

    private func ensureWindow(store: AURAStore) {
        self.store = store
        guard window == nil else { return }

        let panel = CursorSurfaceWindow(
            contentRect: NSRect(origin: .zero, size: Self.textInputPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isExcludedFromWindowsMenu = true
        panel.onEscape = { [weak self] in
            self?.dismissComposerFromEscape()
        }
        panel.contentViewController = NSHostingController(
            rootView: CursorSurfaceView(
                store: store,
                sessionManager: store.sessionManager,
                minimizeSurface: { [weak self] in
                    self?.store?.minimizeAmbientSurface()
                }
            )
        )
        window = panel
        AURATelemetry.info(.ambientPanelCreated, category: .ui)
    }

    private func startEscapeKeyMonitor() {
        guard escapeKeyMonitor == nil else { return }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else {
                return event
            }

            Task { @MainActor in
                self?.dismissComposerFromEscape()
            }
            return nil
        }
    }

    private func stopEscapeKeyMonitor() {
        guard let escapeKeyMonitor else { return }
        NSEvent.removeMonitor(escapeKeyMonitor)
        self.escapeKeyMonitor = nil
    }

    private func dismissComposerFromEscape() {
        guard presentation.isComposerOpen else { return }

        if let store {
            store.minimizeAmbientSurface()
        } else {
            closeBubblePanel()
        }
    }

    private func showCursorOverlay(store: AURAStore) {
        let screens = NSScreen.screens
        if shouldRebuildCursorOverlay(for: screens) {
            hideCursorOverlay()
            let isFirstAppearance = !hasShownCursorOverlay
            hasShownCursorOverlay = true

            for screen in screens {
                let overlayWindow = CursorSurfaceOverlayWindow(screen: screen)
                let contentView = CursorSurfaceOverlayView(
                    screenFrame: screen.frame,
                    isFirstAppearance: isFirstAppearance,
                    store: store,
                    sessionManager: store.sessionManager
                )

                let hostingView = NSHostingView(rootView: contentView)
                hostingView.frame = screen.frame
                hostingView.setAccessibilityElement(false)
                overlayWindow.contentView = hostingView

                overlayWindows.append(overlayWindow)
            }
        }

        for overlayWindow in overlayWindows {
            overlayWindow.alphaValue = 1
            overlayWindow.orderFrontRegardless()
        }
    }

    private func hideCursorOverlay() {
        for overlayWindow in overlayWindows {
            overlayWindow.orderOut(nil)
            overlayWindow.contentView = nil
        }
        overlayWindows.removeAll()
    }

    private func shouldRebuildCursorOverlay(for screens: [NSScreen]) -> Bool {
        guard overlayWindows.count == screens.count else { return true }
        return zip(overlayWindows, screens).contains { overlayWindow, screen in
            overlayWindow.screenFrame != screen.frame
        }
    }

    private func updateCursorOverlayVisibility(store: AURAStore) {
        if presentation.isComposerOpen && shouldShowBubblePanel {
            hideCursorOverlay()
        } else {
            showCursorOverlay(store: store)
        }
    }

    private func updateWindowLayout(animate: Bool) {
        guard let window else { return }

        guard shouldShowBubblePanel else {
            window.orderOut(nil)
            resetBubbleAnchor()
            return
        }

        let size = panelSize
        let origin = anchoredPanelOrigin(for: size)
        window.ignoresMouseEvents = false
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: animate)
        window.orderFrontRegardless()
    }

    private var shouldShowBubblePanel: Bool {
        if displaySessionForBubble != nil {
            return true
        }

        guard let store else { return false }

        switch store.inputMode {
        case .text:
            return true
        case .voice:
            switch store.voiceInputState {
            case .failed:
                return true
            case .idle, .requestingPermission, .recording, .transcribing:
                return false
            }
        }
    }

    private var displaySessionForBubble: MissionSession? {
        guard let store else { return nil }

        if let selectedSession = store.sessionManager.selectedSession {
            return selectedSession
        }

        if let activeSession = store.sessionManager.activeSessions.first {
            return activeSession
        }

        guard let latestSession = store.sessionManager.latestSession,
              latestSession.isFinished else {
            return nil
        }

        return latestSession
    }

    private var panelSize: NSSize {
        if let session = displaySessionForBubble {
            return sessionPanelSize(for: session)
        }

        guard let store else { return Self.textInputPanelSize }
        switch store.inputMode {
        case .text:
            return Self.textInputPanelSize
        case .voice:
            return Self.voiceMessagePanelSize
        }
    }

    private func outputPanelSize(for output: String) -> NSSize {
        let estimatedLines = estimatedOutputLineCount(in: output)
        let height = min(
            max(CGFloat(estimatedLines) * Self.outputLineHeight, Self.outputLineHeight),
            Self.maximumOutputViewportHeight
        )
        return NSSize(width: Self.bubblePanelWidth, height: height)
    }

    private func sessionPanelSize(for session: MissionSession) -> NSSize {
        let outputSize = outputPanelSize(for: outputText(for: session))
        let height = max(outputSize.height + Self.sessionChromeHeight, Self.minimumSessionPanelHeight)
        return NSSize(width: outputSize.width, height: height)
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

    private func panelOrigin(for size: NSSize) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        var origin = NSPoint(x: cursor.x + 22, y: cursor.y - 6 - size.height)

        if let currentScreen = screenContainingPoint(cursor) {
            let visibleFrame = currentScreen.visibleFrame

            if origin.x + size.width > visibleFrame.maxX {
                origin.x = cursor.x - 22 - size.width
            }

            if origin.y < visibleFrame.minY {
                origin.y = cursor.y + 6
            }

            origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - size.width))
            origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - size.height))
        }

        return origin
    }

    private func anchoredPanelOrigin(for size: NSSize) -> NSPoint {
        if let bubbleAnchorTopLeft {
            let visibleFrame = bubbleAnchorVisibleFrame ?? visibleFrameContainingPoint(bubbleAnchorTopLeft)
            return clampedPanelOrigin(
                NSPoint(x: bubbleAnchorTopLeft.x, y: bubbleAnchorTopLeft.y - size.height),
                size: size,
                visibleFrame: visibleFrame
            )
        }

        let origin = panelOrigin(for: size)
        bubbleAnchorTopLeft = NSPoint(x: origin.x, y: origin.y + size.height)
        bubbleAnchorVisibleFrame = visibleFrameContainingPoint(NSPoint(x: origin.x, y: origin.y + size.height))
        return origin
    }

    private func clampedPanelOrigin(_ origin: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - size.width)),
            y: max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - size.height))
        )
    }

    private func resetBubbleAnchor() {
        bubbleAnchorTopLeft = nil
        bubbleAnchorVisibleFrame = nil
    }

    private func visibleFrameContainingPoint(_ point: NSPoint) -> NSRect {
        screenContainingPoint(point)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func screenContainingPoint(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}

@MainActor
final class CursorSurfacePresentation: ObservableObject {
    @Published var isComposerOpen = false
}

private final class CursorSurfaceWindow: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode != UInt16(kVK_Escape) else {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}

private final class CursorSurfaceOverlayWindow: NSWindow {
    let screenFrame: NSRect

    init(screen: NSScreen) {
        self.screenFrame = screen.frame

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hasShadow = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        setFrame(screen.frame, display: true)

        if let screenForWindow = NSScreen.screens.first(where: { $0.frame == screen.frame }) {
            setFrameOrigin(screenForWindow.frame.origin)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
