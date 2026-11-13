import AppKit
import Carbon
import DailyCore

/// Carbon's registered hot key avoids monitoring keystrokes or requiring Accessibility access.
@MainActor
final class GlobalCaptureShortcut: ObservableObject {
    @Published private(set) var error: String?
    @Published private(set) var label = "⌘⇧Space"
    var onCapture: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registeredBinding: ShortcutBinding?

    func register(binding: ShortcutBinding?) {
        guard binding != registeredBinding || (binding != nil && hotKey == nil) else { return }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registeredBinding = binding
        error = nil
        guard let binding else {
            label = "Not set"
            return
        }
        label = KeyboardShortcutCatalog.label(for: binding)
        guard binding.strokes.count == 1, let stroke = binding.strokes.first,
            let code = stroke.carbonKeyCode
        else {
            error = "Choose one supported key combination for global capture in Settings → Keyboard."
            return
        }
        guard installHandlerIfNeeded() else { return }
        registerHotKey(stroke, code: code)
    }

    private func installHandlerIfNeeded() -> Bool {
        guard handler == nil else { return true }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let shortcut = Unmanaged<GlobalCaptureShortcut>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in shortcut.onCapture?() }
                return noErr
            }, 1, &event, pointer, &handler)
        guard installed == noErr else {
            Log.capture.error("Hot-key handler install failed: \(installed, privacy: .public)")
            error = "Could not install the capture shortcut."
            return false
        }
        return true
    }

    private func registerHotKey(_ stroke: ShortcutStroke, code: UInt32) {
        var modifiers: UInt32 = 0
        if stroke.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if stroke.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if stroke.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if stroke.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let result = RegisterEventHotKey(
            code, modifiers, EventHotKeyID(signature: 0x4457_4350, id: 1),
            GetApplicationEventTarget(), 0, &hotKey)
        guard result != noErr else { return }
        if stroke == ShortcutStroke("space", modifiers: [.command, .shift]) {
            let fallback = RegisterEventHotKey(
                UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x4457_4350, id: 1),
                GetApplicationEventTarget(), 0, &hotKey)
            if fallback == noErr {
                Log.capture.notice("⌘⇧Space is reserved; using ⌃⌥Space")
                label = "⌃⌥Space"
                return
            }
        }
        Log.capture.error("Capture shortcut is reserved: \(result, privacy: .public)")
        error = "That global capture shortcut is reserved. Choose another in Settings → Keyboard."
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
