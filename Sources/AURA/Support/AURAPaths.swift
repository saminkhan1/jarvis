import Foundation

enum AURAPaths {
    static var projectRoot: URL {
        if let override = ProcessInfo.processInfo.environment["AURA_PROJECT_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app",
           bundleURL.deletingLastPathComponent().lastPathComponent == "dist" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let root = repositoryRoot(containing: currentDirectory) {
            return root
        }

        if let root = repositoryRoot(containing: bundleURL) {
            return root
        }

        #if DEBUG
        let sourceFile = URL(fileURLWithPath: #filePath, isDirectory: false)
        if let root = repositoryRoot(containing: sourceFile) {
            return root
        }
        #endif

        return currentDirectory
    }

    static var hermesAgentRoot: URL {
        projectRoot.appendingPathComponent(".aura/hermes-agent", isDirectory: true)
    }

    static var hermesHome: URL {
        projectRoot.appendingPathComponent(".aura/hermes-home", isDirectory: true)
    }

    private static func repositoryRoot(containing url: URL) -> URL? {
        let fileManager = FileManager.default
        var candidate = url.hasDirectoryPath ? url : url.deletingLastPathComponent()

        while true {
            let hermesWrapper = candidate.appendingPathComponent("script/aura-hermes")
            let packageManifest = candidate.appendingPathComponent("Package.swift")

            if fileManager.isExecutableFile(atPath: hermesWrapper.path),
               fileManager.fileExists(atPath: packageManifest.path) {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }

            candidate = parent
        }
    }
}
