import AppKit
import DailyCore
import SwiftUI

extension ShortcutStroke {
    /// Unshifted physical keys, shared by NSEvent and the panel's keyed command handler.
    private static let specialKeys: [UInt16: String] = [
        123: "leftArrow", 124: "rightArrow", 125: "downArrow", 126: "upArrow",
        49: "space", 36: "return", 76: "return", 51: "delete", 117: "delete",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
        98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
    ]

    /// The unshifted physical key plus explicit modifiers; no text field or string parser involved.
    init?(event: NSEvent) {
        self.init(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
            modifierFlags: event.modifierFlags)
    }

    init?(keyCode: UInt16, characters: String, modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: ShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if let special = Self.specialKeys[keyCode] {
            self.init(special, modifiers: modifiers)
            return
        }
        guard characters.count == 1 else { return nil }
        self.init(characters.lowercased(), modifiers: modifiers)
    }

    func matches(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        return self == ShortcutStroke(event: event)
    }

    /// Carbon virtual-key code for global hotkeys; unsupported strokes must never be registered.
    var carbonKeyCode: UInt32? {
        switch key {
        case "a": return 0
        case "s": return 1
        case "d": return 2
        case "f": return 3
        case "h": return 4
        case "g": return 5
        case "z": return 6
        case "x": return 7
        case "c": return 8
        case "v": return 9
        case "b": return 11
        case "q": return 12
        case "w": return 13
        case "e": return 14
        case "r": return 15
        case "y": return 16
        case "t": return 17
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "6": return 22
        case "5": return 23
        case "=": return 24
        case "9": return 25
        case "7": return 26
        case "-": return 27
        case "8": return 28
        case "0": return 29
        case "]": return 30
        case "o": return 31
        case "u": return 32
        case "[": return 33
        case "i": return 34
        case "p": return 35
        case "l": return 37
        case "j": return 38
        case "'": return 39
        case "k": return 40
        case ";": return 41
        case "\\": return 42
        case ",": return 43
        case "/": return 44
        case "n": return 45
        case "m": return 46
        case ".": return 47
        case "space": return 49
        case "`": return 50
        default: return nil
        }
    }
}

extension ShortcutBinding {
    /// SwiftUI menu/button equivalent. Typable keys (bare, Shift or Option only) stay in focused event dispatch.
    var menuShortcut: KeyboardShortcut? {
        guard strokes.count == 1, let stroke = strokes.first,
            !stroke.modifiers.isDisjoint(with: [.command, .control])
        else { return nil }
        let key: KeyEquivalent
        switch stroke.key {
        case "leftArrow": key = .leftArrow
        case "rightArrow": key = .rightArrow
        case "upArrow": key = .upArrow
        case "downArrow": key = .downArrow
        case "space": key = .space
        case "return": key = .return
        case "delete": key = .delete
        default:
            guard stroke.key.count == 1, let character = stroke.key.first else { return nil }
            key = KeyEquivalent(character)
        }
        var modifiers: EventModifiers = []
        if stroke.modifiers.contains(.command) { modifiers.insert(.command) }
        if stroke.modifiers.contains(.option) { modifiers.insert(.option) }
        if stroke.modifiers.contains(.control) { modifiers.insert(.control) }
        if stroke.modifiers.contains(.shift) { modifiers.insert(.shift) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}
