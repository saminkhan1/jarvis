import AppKit
import SwiftUI

@main
struct AURAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AURAStore()

    var body: some Scene {
        WindowGroup("AURA", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    await store.runLaunchOnboarding()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("New Mission") {
                    store.showAmbientEntryPoint()
                }
                .keyboardShortcut("a", modifiers: [.control, .option, .command])
                .disabled(!store.canOpenAmbientEntryPoint)

                Button("Refresh Hermes Status") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra("AURA", systemImage: "sparkle.magnifyingglass") {
            MenuBarContentView(store: store)
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isRedirectingRawXcodeExecutable = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        AURATelemetry.info(.appWillFinishLaunching, category: .app, audit: .lifecycle)
        isRedirectingRawXcodeExecutable = XcodeLaunchRedirector.redirectIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRedirectingRawXcodeExecutable else { return }
        AURATelemetry.info(.appDidFinishLaunching, category: .app, audit: .lifecycle)
        NSApp.setActivationPolicy(.regular)
        bringMainWindowForward()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.bringMainWindowForward()
        }
    }

    private func bringMainWindowForward() {
        var didFindMainWindow = false
        for window in NSApp.windows where window.title == "AURA" {
            didFindMainWindow = true
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        AURATelemetry.info(
            .mainWindowActivated,
            category: .app,
            fields: [.bool("found_window", didFindMainWindow)]
        )
    }
}
