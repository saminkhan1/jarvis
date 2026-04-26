import AppKit
import Foundation

enum XcodeLaunchRedirector {
    @MainActor
    static func redirectIfNeeded() -> Bool {
        #if DEBUG
        guard Bundle.main.bundleURL.pathExtension != "app" else { return false }

        let environment = ProcessInfo.processInfo.environment
        guard environment["AURA_DISABLE_XCODE_APP_REDIRECT"] != "1" else { return false }

        guard let executableURL = Bundle.main.executableURL else {
            AURATelemetry.error(
                .xcodeRedirectSkipped,
                category: .launch,
                fields: [.string("reason", "missing_executable_url")]
            )
            return false
        }

        do {
            let startedAt = Date()
            let bundleURL = try stageAppBundle(executableURL: executableURL)
            try openAppBundle(bundleURL)
            AURATelemetry.info(
                .xcodeRedirectSuccess,
                category: .launch,
                fields: [
                    .privateValue("bundle_path"),
                    .int("duration_ms", AURATelemetry.durationMilliseconds(from: startedAt))
                ]
            )
            NSApp.terminate(nil)
            return true
        } catch {
            AURATelemetry.error(
                .xcodeRedirectFailed,
                category: .launch,
                fields: [.string("error_type", String(describing: type(of: error)))]
            )
            return false
        }
        #else
        return false
        #endif
    }

    private static func stageAppBundle(executableURL: URL) throws -> URL {
        let root = AURAPaths.projectRoot
        let bundleURL = root.appendingPathComponent(".aura/xcode/AURA.app", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let stagedExecutableURL = macOSURL.appendingPathComponent("AURA")
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let fileManager = FileManager.default

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.wexprolabs.aura")
        for app in runningApps where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.terminate()
        }

        if fileManager.fileExists(atPath: bundleURL.path) {
            try fileManager.removeItem(at: bundleURL)
        }

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: executableURL, to: stagedExecutableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedExecutableURL.path)
        try infoPlistXML.write(to: infoPlistURL, atomically: true, encoding: .utf8)
        try signAppBundle(bundleURL)

        return bundleURL
    }

    private static func openAppBundle(_ bundleURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path]
        process.currentDirectoryURL = AURAPaths.projectRoot
        try process.run()
    }

    private static func signAppBundle(_ bundleURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", bundleURL.path]
        process.currentDirectoryURL = AURAPaths.projectRoot
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw CocoaError(.executableLoad)
        }
    }

    private static var infoPlistXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleExecutable</key>
          <string>AURA</string>
          <key>CFBundleIdentifier</key>
          <string>com.wexprolabs.aura</string>
          <key>CFBundleName</key>
          <string>AURA</string>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
          <key>LSMinimumSystemVersion</key>
          <string>14.0</string>
          <key>NSPrincipalClass</key>
          <string>NSApplication</string>
        </dict>
        </plist>
        """
    }
}
