import Foundation
import Carbon
import AppKit

public final class HotKeyManager: @unchecked Sendable {
    public static let shared = HotKeyManager()

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var isRegistered = false

    private init() {}

    public func register() {
        guard !isRegistered else { return }
        isRegistered = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                DispatchQueue.main.async {
                    WindowRouter.triggerOpen()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4147594D), // "AGYM"
            id: 1
        )

        let modifiers = UInt32(controlKey | optionKey)
        let keyCode = UInt32(kVK_ANSI_A) // 'A' key

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
