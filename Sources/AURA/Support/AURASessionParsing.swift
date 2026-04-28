import Foundation

enum AURASessionParsing {
    static func sessionID(in output: String) -> String? {
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.lowercased().hasPrefix("session_id:") else { continue }

            let value = line
                .dropFirst("session_id:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        return nil
    }

    static func sessionSummaries(in export: String, source: String, limit: Int) -> SessionSummariesResult {
        guard limit > 0 else {
            return SessionSummariesResult(summaries: [], malformedRecordCount: 0)
        }

        let records = export
            .split(whereSeparator: \.isNewline)
            .map(decodeExportRecord)

        let malformedRecordCount = records.reduce(into: 0) { count, record in
            if record == nil {
                count += 1
            }
        }

        let summaries = records
            .compactMap { $0 }
            .filter { $0.source == source }
            .sorted { lhs, rhs in
                if lhs.lastActive == rhs.lastActive {
                    return lhs.startedAt > rhs.startedAt
                }
                return lhs.lastActive > rhs.lastActive
            }
            .prefix(limit)
            .map { record in
                HermesSessionSummary(
                    id: record.id,
                    preview: preview(for: record),
                    lastActive: Date(timeIntervalSince1970: record.lastActive),
                    messageCount: record.messageCount
                )
            }

        return SessionSummariesResult(
            summaries: Array(summaries),
            malformedRecordCount: malformedRecordCount
        )
    }

    private static func decodeExportRecord(line: Substring) -> ExportRecord? {
        guard let data = String(line).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ExportRecord.self, from: data)
    }

    private static func preview(for record: ExportRecord) -> String {
        let firstUserContent = record.messages
            .first { $0.role == "user" }?
            .content ?? ""

        if let taggedPreview = extractTaggedUserMessage(from: firstUserContent), !taggedPreview.isEmpty {
            return taggedPreview
        }

        // Compatibility shim for pre-PR4 AURA envelope sessions.
        if let goalPreview = extractSection(named: "USER GOAL", from: firstUserContent), !goalPreview.isEmpty {
            return goalPreview
        }

        let normalized = normalizePreview(firstUserContent)
        return normalized.isEmpty ? "Session \(record.id)" : normalized
    }


    private static func extractTaggedUserMessage(from content: String) -> String? {
        let openTag = "<user_message source=\"aura\">"
        let closeTag = "</user_message>"
        guard let openRange = content.range(of: openTag),
              let closeRange = content.range(of: closeTag, range: openRange.upperBound..<content.endIndex) else {
            return nil
        }

        let escapedMessage = String(content[openRange.upperBound..<closeRange.lowerBound])
        let unescapedMessage = xmlUnescaped(escapedMessage)
        let normalized = normalizePreview(unescapedMessage)
        return normalized.isEmpty ? nil : normalized
    }

    private static func xmlUnescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func extractSection(named heading: String, from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == heading
        }) else {
            return nil
        }

        var collected: [String] = []
        for line in lines.dropFirst(headingIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !collected.isEmpty {
                    break
                }
                continue
            }

            if isEnvelopeHeading(trimmed) {
                break
            }

            collected.append(trimmed)
        }

        let preview = normalizePreview(collected.joined(separator: " "))
        return preview.isEmpty ? nil : preview
    }

    private static func normalizePreview(_ content: String) -> String {
        let filteredLines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty &&
                !isEnvelopeHeading(line) &&
                !line.hasPrefix("- ")
            }

        let collapsed = filteredLines.joined(separator: " ")
        let normalizedWhitespace = collapsed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalizedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isEnvelopeHeading(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized == "AURA MISSION CONTEXT" ||
            normalized == "AURA MISSION ENVELOPE" ||
            normalized == "USER GOAL" ||
            normalized == "CURRENT MAC CONTEXT" ||
            normalized == "CUA READINESS"
    }
}

private struct ExportRecord: Decodable {
    let id: String
    let source: String
    let startedAt: TimeInterval
    let lastActive: TimeInterval
    let endedAt: TimeInterval?
    let messageCount: Int
    let messages: [ExportMessage]

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case startedAt = "started_at"
        case lastActive = "last_active"
        case endedAt = "ended_at"
        case messageCount = "message_count"
        case messages
    }
}

private struct ExportMessage: Decodable {
    let role: String
    let content: String?
}

struct SessionSummariesResult: Equatable {
    let summaries: [HermesSessionSummary]
    let malformedRecordCount: Int
}
