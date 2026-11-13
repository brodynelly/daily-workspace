import Foundation

/// Portable shortcut representation; the app translates these symbols to AppKit events.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let control = Self(rawValue: 4)
    public static let shift = Self(rawValue: 8)

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt8.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ShortcutStroke: Codable, Equatable, Hashable, Sendable {
    /// Lowercase ASCII character, or leftArrow, rightArrow, upArrow, downArrow, space, return, delete.
    public var key: String
    public var modifiers: ShortcutModifiers

    public init(_ key: String, modifiers: ShortcutModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// One or two strokes; nil in an override explicitly means the command is unbound.
public struct ShortcutBinding: Codable, Equatable, Hashable, Sendable {
    public let strokes: [ShortcutStroke]
    private enum CodingKeys: String, CodingKey { case strokes }

    public init(_ first: ShortcutStroke, _ second: ShortcutStroke? = nil) {
        strokes = second.map { [first, $0] } ?? [first]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let strokes = try container.decode([ShortcutStroke].self, forKey: .strokes)
        guard (1...2).contains(strokes.count) else {
            throw DecodingError.dataCorruptedError(
                forKey: .strokes, in: container, debugDescription: "Expected one or two shortcut strokes")
        }
        self.strokes = strokes
    }
}

/// Presence of this value overrides the default; `binding: nil` explicitly disables the shortcut.
public struct ShortcutOverride: Codable, Equatable, Sendable {
    public let binding: ShortcutBinding?

    public init(_ binding: ShortcutBinding?) { self.binding = binding }

    private enum CodingKeys: String, CodingKey { case binding }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.binding) else {
            throw DecodingError.keyNotFound(
                CodingKeys.binding,
                .init(codingPath: container.codingPath, debugDescription: "Expected binding or explicit null"))
        }
        binding = try container.decodeIfPresent(ShortcutBinding.self, forKey: .binding)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let binding {
            try container.encode(binding, forKey: .binding)
        } else {
            try container.encodeNil(forKey: .binding)
        }
    }
}
