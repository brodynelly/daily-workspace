import AppKit
import Carbon

/// Carbon's registered hot key avoids monitoring keystrokes or requiring Accessibility access.
@MainActor
final class GlobalCaptureShortcut: ObservableObject {
    @Published private(set) var error: String?
    @Published private(set) var label = "⌘⇧Space"
    var onCapture: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() {
        guard hotKey == nil, handler == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalCaptureShortcut>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in shortcut.onCapture?() }
            return noErr
        }, 1, &event, pointer, &handler)
        guard installed == noErr else { error = "Could not install the capture shortcut."; return }
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x44574350, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr {
            let fallback = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x44574350, id: 1), GetApplicationEventTarget(), 0, &hotKey)
            if fallback == noErr { label = "⌃⌥Space" }
            else { error = "Capture shortcuts are reserved by other apps. Use the menu-bar Capture action or ⌘⌥N in the workspace." }
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
