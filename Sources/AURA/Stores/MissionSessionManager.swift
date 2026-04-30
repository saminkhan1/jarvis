import Foundation

@MainActor
final class MissionSessionManager: ObservableObject {
    @Published private(set) var sessions: [MissionSession] = []
    @Published var selectedSessionID: UUID?

    var onSessionsChanged: (() -> Void)?

    private let hermesService: HermesService

    init(hermesService: HermesService = HermesService()) {
        self.hermesService = hermesService
    }

    @discardableResult
    func spawnSession(
        for input: String,
        context: ContextSnapshot? = nil,
        traceID: String = AURATelemetry.makeTraceID(prefix: "mission"),
        missionID: String = AURATelemetry.makeSpanID(prefix: "mission"),
        selectOnStart: Bool = false
    ) -> MissionSession? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let session = MissionSession(
            prompt: trimmed,
            context: context,
            hermesService: hermesService,
            traceID: traceID,
            missionID: missionID
        )
        session.onStateChanged = { [weak self] in
            self?.notifySessionsChanged()
        }

        sessions.insert(session, at: 0)
        selectedSessionID = selectOnStart ? session.id : nil
        notifySessionsChanged()

        AURATelemetry.info(
            .missionStartRequested,
            category: .mission,
            traceID: traceID,
            fields: [
                .string("mission_id", missionID),
                .string("operation", "invoke_agent"),
                .int("goal_chars", trimmed.count),
                .int("active_session_count", activeSessions.count)
            ],
            audit: .mission
        )

        session.start()
        return session
    }

    func selectComposer() {
        selectedSessionID = nil
        notifySessionsChanged()
    }

    func selectSession(_ id: UUID) {
        selectedSessionID = id
        notifySessionsChanged()
    }

    func cancelSession(_ id: UUID) {
        sessions.first { $0.id == id }?.cancel()
    }

    func removeSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = nil
        }
        notifySessionsChanged()
    }

    func cancelAllActiveSessions() {
        for session in activeSessions {
            session.cancel()
        }
    }

    func dismissFinishedSessions() {
        for session in sessions where session.isFinished {
            removeSession(session.id)
        }
    }

    var selectedSession: MissionSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var activeSessions: [MissionSession] {
        sessions.filter { $0.status == .running }
    }

    var hasActiveSessions: Bool {
        !activeSessions.isEmpty
    }

    var latestSession: MissionSession? {
        sessions.first
    }

    var displaySession: MissionSession? {
        selectedSession ?? latestSession
    }

    var dominantStatus: MissionStatus {
        if hasActiveSessions {
            return .running
        }

        return latestSession?.status ?? .idle
    }

    var statusSummary: String {
        let active = activeSessions.count
        let total = sessions.count

        if active > 0 {
            return "\(active) running, \(total) total"
        }

        if total > 0 {
            return "\(total) session\(total == 1 ? "" : "s")"
        }

        return "No sessions"
    }

    private func notifySessionsChanged() {
        objectWillChange.send()
        onSessionsChanged?()
    }
}
