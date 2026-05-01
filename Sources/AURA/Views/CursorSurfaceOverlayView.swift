import AppKit
import SwiftUI

struct CursorSurfaceOverlayView: View {
    let screenFrame: CGRect
    let isFirstAppearance: Bool
    @ObservedObject var store: AURAStore
    @ObservedObject var sessionManager: MissionSessionManager

    @State private var cursorPosition: CGPoint
    @State private var isCursorOnThisScreen: Bool
    @State private var timer: Timer?
    @State private var welcomeText = ""
    @State private var showWelcome = true
    @State private var bubbleSize: CGSize = .zero
    @State private var bubbleOpacity = 1.0
    @State private var cursorOpacity = 0.0

    private let fullWelcomeMessage = "hey! i'm clicky"

    init(
        screenFrame: CGRect,
        isFirstAppearance: Bool,
        store: AURAStore,
        sessionManager: MissionSessionManager
    ) {
        self.screenFrame = screenFrame
        self.isFirstAppearance = isFirstAppearance
        self.store = store
        self.sessionManager = sessionManager

        let mouseLocation = NSEvent.mouseLocation
        let localX = mouseLocation.x - screenFrame.origin.x
        let localY = screenFrame.height - (mouseLocation.y - screenFrame.origin.y)
        _cursorPosition = State(initialValue: CGPoint(x: localX + 35, y: localY + 25))
        _isCursorOnThisScreen = State(initialValue: screenFrame.contains(mouseLocation))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)

            if isCursorOnThisScreen && showWelcome && !welcomeText.isEmpty {
                ClickyCursorBubble(text: welcomeText)
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: CursorSurfaceBubbleSizePreferenceKey.self, value: geo.size)
                        }
                    )
                    .opacity(bubbleOpacity)
                    .position(x: cursorPosition.x + 10 + (bubbleSize.width / 2), y: cursorPosition.y + 18)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                    .animation(.easeOut(duration: 0.5), value: bubbleOpacity)
                    .onPreferenceChange(CursorSurfaceBubbleSizePreferenceKey.self) { newSize in
                        bubbleSize = newSize
                    }
            }

            ClickyCursorTriangle()
                .fill(ClickyCursorStyle.overlayCursorBlue)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(-35))
                .shadow(color: ClickyCursorStyle.overlayCursorBlue, radius: 8, x: 0, y: 0)
                .opacity(isCursorOnThisScreen && (cursorMode == .idle || cursorMode == .responding) ? cursorOpacity : 0)
                .position(cursorPosition)
                .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                .animation(.easeIn(duration: 0.25), value: cursorMode)

            BlueCursorWaveformView(audioPowerLevel: CGFloat(store.voiceInputLevel))
                .opacity(isCursorOnThisScreen && cursorMode == .listening ? cursorOpacity : 0)
                .position(cursorPosition)
                .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                .animation(.easeIn(duration: 0.15), value: cursorMode)

            BlueCursorSpinnerView()
                .opacity(isCursorOnThisScreen && cursorMode == .processing ? cursorOpacity : 0)
                .position(cursorPosition)
                .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                .animation(.easeIn(duration: 0.15), value: cursorMode)
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            let mouseLocation = NSEvent.mouseLocation
            isCursorOnThisScreen = screenFrame.contains(mouseLocation)

            let swiftUIPosition = convertScreenPointToSwiftUICoordinates(mouseLocation)
            cursorPosition = CGPoint(x: swiftUIPosition.x + 35, y: swiftUIPosition.y + 25)

            startTrackingCursor()

            if isFirstAppearance && isCursorOnThisScreen {
                withAnimation(.easeIn(duration: 2.0)) {
                    cursorOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.bubbleOpacity = 0.0
                    self.startWelcomeAnimation()
                }
            } else {
                cursorOpacity = 1.0
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var cursorMode: CursorSurfaceOverlayMode {
        if store.inputMode == .voice {
            switch store.voiceInputState {
            case .recording:
                return .listening
            case .requestingPermission, .transcribing:
                return .processing
            case .idle, .failed:
                break
            }
        }

        if sessionManager.hasActiveSessions || store.isRunningCuaOnboarding {
            return .processing
        }

        if sessionManager.latestSession?.isFinished == true {
            return .responding
        }

        return .idle
    }

    private func startTrackingCursor() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            let mouseLocation = NSEvent.mouseLocation
            self.isCursorOnThisScreen = self.screenFrame.contains(mouseLocation)

            let swiftUIPosition = self.convertScreenPointToSwiftUICoordinates(mouseLocation)
            let buddyX = swiftUIPosition.x + 35
            let buddyY = swiftUIPosition.y + 25
            self.cursorPosition = CGPoint(x: buddyX, y: buddyY)
        }
    }

    private func convertScreenPointToSwiftUICoordinates(_ screenPoint: CGPoint) -> CGPoint {
        let x = screenPoint.x - screenFrame.origin.x
        let y = (screenFrame.origin.y + screenFrame.height) - screenPoint.y
        return CGPoint(x: x, y: y)
    }

    private func startWelcomeAnimation() {
        withAnimation(.easeIn(duration: 0.4)) {
            bubbleOpacity = 1.0
        }

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            guard currentIndex < self.fullWelcomeMessage.count else {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.bubbleOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.showWelcome = false
                }
                return
            }

            let index = self.fullWelcomeMessage.index(self.fullWelcomeMessage.startIndex, offsetBy: currentIndex)
            self.welcomeText.append(self.fullWelcomeMessage[index])
            currentIndex += 1
        }
    }
}

private enum CursorSurfaceOverlayMode: Equatable {
    case idle
    case listening
    case processing
    case responding
}

private enum ClickyCursorStyle {
    static let overlayCursorBlue = Color(hex: "#3380FF")
}

private struct CursorSurfaceBubbleSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct ClickyCursorTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size = min(rect.width, rect.height)
        let height = size * sqrt(3.0) / 2.0

        path.move(to: CGPoint(x: rect.midX, y: rect.midY - height / 1.5))
        path.addLine(to: CGPoint(x: rect.midX - size / 2, y: rect.midY + height / 3))
        path.addLine(to: CGPoint(x: rect.midX + size / 2, y: rect.midY + height / 3))
        path.closeSubpath()
        return path
    }
}

private struct ClickyCursorBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ClickyCursorStyle.overlayCursorBlue)
                    .shadow(color: ClickyCursorStyle.overlayCursorBlue.opacity(0.5), radius: 6, x: 0, y: 0)
            )
            .fixedSize()
    }
}

private struct BlueCursorWaveformView: View {
    let audioPowerLevel: CGFloat

    private let barCount = 5
    private let listeningBarProfile: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 36.0)) { timelineContext in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { barIndex in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(ClickyCursorStyle.overlayCursorBlue)
                        .frame(
                            width: 2,
                            height: barHeight(
                                for: barIndex,
                                timelineDate: timelineContext.date
                            )
                        )
                }
            }
            .shadow(color: ClickyCursorStyle.overlayCursorBlue.opacity(0.6), radius: 6, x: 0, y: 0)
            .animation(.linear(duration: 0.08), value: audioPowerLevel)
        }
    }

    private func barHeight(for barIndex: Int, timelineDate: Date) -> CGFloat {
        let animationPhase = CGFloat(timelineDate.timeIntervalSinceReferenceDate * 3.6) + CGFloat(barIndex) * 0.35
        let normalizedAudioPowerLevel = max(audioPowerLevel - 0.008, 0)
        let easedAudioPowerLevel = pow(min(normalizedAudioPowerLevel * 2.85, 1), 0.76)
        let reactiveHeight = easedAudioPowerLevel * 10 * listeningBarProfile[barIndex]
        let idlePulse = (sin(animationPhase) + 1) / 2 * 1.5
        return 3 + reactiveHeight + idlePulse
    }
}

private struct BlueCursorSpinnerView: View {
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(
                AngularGradient(
                    colors: [
                        ClickyCursorStyle.overlayCursorBlue.opacity(0.0),
                        ClickyCursorStyle.overlayCursorBlue
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .shadow(color: ClickyCursorStyle.overlayCursorBlue.opacity(0.6), radius: 6, x: 0, y: 0)
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
            }
    }
}
