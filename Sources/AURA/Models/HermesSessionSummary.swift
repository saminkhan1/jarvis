import Foundation

struct HermesSessionSummary: Identifiable {
    let id: String
    let source: String
    let model: String
    let preview: String
    let startedAt: Date?
    let endedAt: Date?
    let messageCount: Int
    let toolCallCount: Int

    var displayDate: Date? {
        endedAt ?? startedAt
    }

    var statusTitle: String {
        endedAt == nil ? "Open" : "Ended"
    }

    static func parseJSONL(_ text: String, limit: Int) -> [HermesSessionSummary] {
        text
            .split(separator: "\n")
            .compactMap { HermesSessionSummary(jsonLine: String($0)) }
            .prefix(limit)
            .map { $0 }
    }

    private init?(jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8),
              let exported = try? JSONDecoder().decode(ExportedHermesSession.self, from: data) else {
            return nil
        }

        id = exported.id
        source = exported.source ?? "unknown"
        model = exported.model ?? "unknown"
        startedAt = exported.startedAt.map(Date.init(timeIntervalSince1970:))
        endedAt = exported.endedAt.map(Date.init(timeIntervalSince1970:))
        messageCount = exported.messageCount ?? exported.messages?.count ?? 0
        toolCallCount = exported.toolCallCount ?? 0

        let candidate = exported.title?.nilIfBlank
            ?? exported.messages?.first { $0.role == "user" }?.content.nilIfBlank
            ?? "Untitled Hermes session"
        preview = candidate.collapsedWhitespace(maxLength: 96)
    }
}

private struct ExportedHermesSession: Decodable {
    let id: String
    let source: String?
    let model: String?
    let title: String?
    let startedAt: Double?
    let endedAt: Double?
    let messageCount: Int?
    let toolCallCount: Int?
    let messages: [ExportedHermesMessage]?

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case model
        case title
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case messageCount = "message_count"
        case toolCallCount = "tool_call_count"
        case messages
    }
}

private struct ExportedHermesMessage: Decodable {
    let role: String
    let content: String
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func collapsedWhitespace(maxLength: Int) -> String {
        let collapsed = split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength - 1)) + "..."
    }
}
