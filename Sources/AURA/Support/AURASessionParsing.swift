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
}
