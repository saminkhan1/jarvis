import Foundation

enum AURARuntimeChecks {
    static func missingMCPCommandPaths(projectRoot: URL = AURAPaths.projectRoot) -> [String] {
        let configURL = projectRoot.appendingPathComponent(".aura/hermes-home/config.yaml")
        guard let config = try? String(contentsOf: configURL, encoding: .utf8) else {
            return []
        }
        return missingMCPCommandPaths(in: config, projectRoot: projectRoot)
    }

    static func missingMCPCommandPaths(in config: String, projectRoot: URL) -> [String] {
        let fileManager = FileManager.default
        return mcpCommandPaths(in: config, projectRoot: projectRoot)
            .filter { !fileManager.isExecutableFile(atPath: $0) && !fileManager.fileExists(atPath: $0) }
    }

    static func mcpCommandPaths(in config: String, projectRoot: URL) -> [String] {
        config
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { rawLine -> String? in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("command:") else { return nil }
                let value = line.dropFirst("command:".count).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
                guard !value.isEmpty else { return nil }
                return value.replacingOccurrences(of: "${AURA_PROJECT_ROOT}", with: projectRoot.path)
            }
    }
}
