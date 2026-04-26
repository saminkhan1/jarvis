import AppKit

@MainActor
final class CursorIndicatorController {
    private static let panelSize = NSSize(width: 360, height: 154)
    private static let cursorOffset = NSPoint(x: 14, y: -170)

    private let window: NSPanel
    private let assistantView: CursorAssistantView
    private var timer: Timer?
    private var lastOrderFrontAt = Date.distantPast
    private var isVisible = false

    init() {
        let frame = NSRect(origin: .zero, size: Self.panelSize)
        assistantView = CursorAssistantView(frame: frame)
        window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = assistantView
    }

    func setVisible(_ isVisible: Bool) {
        if self.isVisible != isVisible {
            AURATelemetry.info(
                .cursorIndicatorVisibilityChanged,
                category: .ui,
                fields: [.bool("visible", isVisible)]
            )
            self.isVisible = isVisible
        }

        if isVisible {
            window.orderFrontRegardless()
            lastOrderFrontAt = Date()
            startTracking()
        } else {
            stopTracking()
            window.orderOut(nil)
        }
    }

    func update(
        status: MissionStatus,
        isShortcutActive: Bool,
        missionOutput: String,
        pendingApprovalTitle: String?,
        automationPolicyTitle: String
    ) {
        assistantView.content = CursorAssistantContent(
            status: status,
            isShortcutActive: isShortcutActive,
            message: Self.message(
                for: status,
                isShortcutActive: isShortcutActive,
                missionOutput: missionOutput,
                pendingApprovalTitle: pendingApprovalTitle
            ),
            actionHint: Self.actionHint(
                for: status,
                isShortcutActive: isShortcutActive,
                missionOutput: missionOutput,
                automationPolicyTitle: automationPolicyTitle
            ),
            color: color(for: status, isShortcutActive: isShortcutActive)
        )
        assistantView.needsDisplay = true
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

    private func positionNearCursor() {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(
            x: cursor.x + Self.cursorOffset.x,
            y: cursor.y + Self.cursorOffset.y
        )

        if origin.x + Self.panelSize.width > visibleFrame.maxX {
            origin.x = cursor.x - Self.panelSize.width - 18
        }

        if origin.y < visibleFrame.minY {
            origin.y = cursor.y + 30
        }

        origin.x = min(max(origin.x, visibleFrame.minX + 10), visibleFrame.maxX - Self.panelSize.width - 10)
        origin.y = min(max(origin.y, visibleFrame.minY + 10), visibleFrame.maxY - Self.panelSize.height - 10)
        window.setFrameOrigin(origin)

        let now = Date()
        if now.timeIntervalSince(lastOrderFrontAt) > 1 {
            window.orderFrontRegardless()
            lastOrderFrontAt = now
        }
    }

    private func color(for status: MissionStatus, isShortcutActive: Bool) -> NSColor {
        if isShortcutActive {
            return .systemGreen
        }

        switch status {
        case .idle:
            return .systemBlue
        case .needsApproval:
            return .systemOrange
        case .running:
            return .systemPurple
        case .completed:
            return .systemGreen
        case .failed:
            return .systemRed
        case .cancelled:
            return .systemGray
        }
    }

    private static func message(
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

    private static func actionHint(
        for status: MissionStatus,
        isShortcutActive: Bool,
        missionOutput: String,
        automationPolicyTitle: String
    ) -> String {
        if isShortcutActive {
            return "Type in the panel, then press Command-Return."
        }

        switch status {
        case .idle:
            return "Control-Option-Command-A opens the panel. Policy: \(automationPolicyTitle)."
        case .running:
            return "I will update here while Hermes works."
        case .needsApproval:
            return "Open the panel to approve or deny."
        case .completed:
            if let recommendedAction = recommendedAction(from: missionOutput) {
                return compact("Next: \(recommendedAction)", limit: 92)
            }
            return "Open the panel to start another request."
        case .failed:
            return "Open the panel or dashboard for details."
        case .cancelled:
            return "Open the panel to start again."
        }
    }

    private static func latestMeaningfulLine(in output: String) -> String? {
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

    private static func finalSummary(from output: String) -> String? {
        let lines = cleanedLines(from: output)

        guard !lines.isEmpty else { return nil }

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

    private static func recommendedAction(from output: String) -> String? {
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

private struct CursorAssistantContent {
    var status: MissionStatus = .idle
    var isShortcutActive = false
    var message = "Ask me to inspect, explain, research, or operate."
    var actionHint = "Control-Option-Command-A opens the panel."
    var color: NSColor = .systemBlue
}

private final class CursorAssistantView: NSView {
    var content = CursorAssistantContent()

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBubble()
        drawPaperclip()
    }

    private func drawBubble() {
        let bubbleRect = NSRect(x: 88, y: 10, width: 258, height: 120)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bubbleRect.minX + 2, y: bubbleRect.maxY - 30))
        tail.line(to: NSPoint(x: 70, y: bubbleRect.maxY - 18))
        tail.line(to: NSPoint(x: bubbleRect.minX + 10, y: bubbleRect.maxY - 8))
        tail.close()

        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        tail.fill()

        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 13, yRadius: 13)
        bubble.fill()

        content.color.withAlphaComponent(0.72).setStroke()
        bubble.lineWidth = 1.4
        bubble.stroke()

        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        tail.lineWidth = 1
        tail.stroke()

        drawText(
            content.message,
            in: NSRect(x: bubbleRect.minX + 14, y: bubbleRect.minY + 14, width: bubbleRect.width - 28, height: 64),
            font: .systemFont(ofSize: 12.5, weight: .medium),
            color: .labelColor
        )

        drawText(
            content.actionHint,
            in: NSRect(x: bubbleRect.minX + 14, y: bubbleRect.maxY - 38, width: bubbleRect.width - 28, height: 24),
            font: .systemFont(ofSize: 10.5, weight: .regular),
            color: .secondaryLabelColor
        )
    }

    private func drawPaperclip() {
        let shadowRect = NSRect(x: 12, y: 122, width: 64, height: 13)
        NSColor.black.withAlphaComponent(0.13).setFill()
        NSBezierPath(ovalIn: shadowRect).fill()

        content.color.withAlphaComponent(content.isShortcutActive ? 0.28 : 0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: 21, y: 21, width: 52, height: 52)).fill()

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 45, y: 112))
        body.curve(
            to: NSPoint(x: 37, y: 30),
            controlPoint1: NSPoint(x: 18, y: 111),
            controlPoint2: NSPoint(x: 15, y: 35)
        )
        body.curve(
            to: NSPoint(x: 65, y: 46),
            controlPoint1: NSPoint(x: 55, y: 25),
            controlPoint2: NSPoint(x: 72, y: 31)
        )
        body.curve(
            to: NSPoint(x: 42, y: 94),
            controlPoint1: NSPoint(x: 56, y: 67),
            controlPoint2: NSPoint(x: 35, y: 77)
        )
        body.curve(
            to: NSPoint(x: 57, y: 71),
            controlPoint1: NSPoint(x: 47, y: 105),
            controlPoint2: NSPoint(x: 61, y: 88)
        )

        NSColor.white.withAlphaComponent(0.72).setStroke()
        body.lineWidth = 13
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        body.stroke()

        NSColor.systemGray.withAlphaComponent(0.95).setStroke()
        body.lineWidth = 8
        body.stroke()

        NSColor.white.withAlphaComponent(0.7).setStroke()
        body.lineWidth = 2.2
        body.stroke()

        drawEye(center: NSPoint(x: 34, y: 53))
        drawEye(center: NSPoint(x: 51, y: 55))

        let brow = NSBezierPath()
        brow.move(to: NSPoint(x: 28, y: 45))
        brow.line(to: NSPoint(x: 38, y: 42))
        brow.move(to: NSPoint(x: 47, y: 43))
        brow.line(to: NSPoint(x: 58, y: 47))
        NSColor.labelColor.withAlphaComponent(0.75).setStroke()
        brow.lineWidth = 2
        brow.lineCapStyle = .round
        brow.stroke()

        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: 35, y: 71))
        mouth.curve(to: NSPoint(x: 52, y: 72), controlPoint1: NSPoint(x: 40, y: 77), controlPoint2: NSPoint(x: 48, y: 78))
        NSColor.labelColor.withAlphaComponent(0.55).setStroke()
        mouth.lineWidth = 2
        mouth.lineCapStyle = .round
        mouth.stroke()
    }

    private func drawEye(center: NSPoint) {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)).fill()

        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 2, y: center.y - 1.5, width: 4, height: 4)).fill()
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        NSString(string: text).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }
}
