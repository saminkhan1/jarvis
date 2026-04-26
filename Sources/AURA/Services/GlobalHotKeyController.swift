import Carbon
import AppKit
import Foundation

final class GlobalHotKeyController {
    private let onPress: @MainActor () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var localMonitor: Any?

    init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
    }

    deinit {
        unregister()
    }

    func register() {
        registerLocalMonitorIfNeeded()
        guard hotKeyRef == nil else { return }

        let hotKeyID = EventHotKeyID(signature: Self.fourCharCode("AURA"), id: 1)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            hotKeyRef = nil
            AURATelemetry.error(
                .hotkeyRegisterFailed,
                category: .hotKey,
                fields: [.int32("status", status)]
            )
            return
        }
        AURATelemetry.info(.hotkeyRegistered, category: .hotKey)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }

                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                Task { @MainActor in
                    AURATelemetry.info(.hotkeyPressedGlobal, category: .hotKey)
                    controller.onPress()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        AURATelemetry.info(.hotkeyEventHandlerInstalled, category: .hotKey)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            AURATelemetry.info(.hotkeyUnregistered, category: .hotKey)
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func registerLocalMonitorIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isAmbientShortcut(event) else { return event }

            Task { @MainActor in
                AURATelemetry.info(.hotkeyPressedLocal, category: .hotKey)
                self?.onPress()
            }

            return nil
        }
    }

    private static func isAmbientShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.control),
              modifiers.contains(.option),
              modifiers.contains(.command) else { return false }

        return event.keyCode == UInt16(kVK_ANSI_A)
    }

    private static func fourCharCode(_ string: String) -> OSType {
        string
            .utf8
            .prefix(4)
            .reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }
}
