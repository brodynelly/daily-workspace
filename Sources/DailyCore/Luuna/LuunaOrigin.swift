import Foundation

/// Why a string is not an acceptable Luuna runtime origin. The cases follow `loopbackUrl` in Luuna's
/// TypeScript client; the app supplies the wording.
public enum LuunaOriginError: Error, Equatable, Sendable {
    /// Not parseable as a URL (for example a port that is not a number from 0 to 65535).
    case malformed
    /// Not `http`, or the host is not `127.0.0.1`, `localhost` or `[::1]`.
    case notHTTPLoopback
    /// Loopback, but with credentials, a query, a fragment or a path prefix.
    case notBareOrigin
}

/// The address of a Luuna runtime: plain HTTP on this Mac's loopback interface, and nothing else.
///
/// Mirrors `loopbackUrl` in `packages/api-client/src/index.ts`: the scheme is `http`, the host is `127.0.0.1`,
/// `localhost` or `[::1]`, a port is optional, and credentials, a query, a fragment or a path prefix are refused.
/// The bearer token is only ever sent to an origin that passed this check.
///
/// It is stricter than the WHATWG parser behind the TypeScript check on spellings that parser rewrites into a
/// loopback address (`127.1`, `[0:0::1]`, `http:\\…`, an empty `user@`): those are refused, never rewritten.
public struct LuunaOrigin: Hashable, Sendable, CustomStringConvertible {
    public enum Host: String, Sendable, CaseIterable {
        case ipv4Loopback = "127.0.0.1"
        case localhost
        case ipv6Loopback = "[::1]"
    }

    /// The port the Luuna runtime listens on unless it was started with another one.
    public static let defaultPort = 4242
    /// `http://127.0.0.1:4242`.
    public static let standard = LuunaOrigin(host: .ipv4Loopback, normalizedPort: defaultPort)

    public let host: Host
    /// The explicit port, or nil for HTTP's default port 80, which an origin never spells out.
    public let port: Int?

    public init(host: Host, port: Int?) throws {
        guard port.map({ (0...65_535).contains($0) }) ?? true else { throw LuunaOriginError.malformed }
        self.init(host: host, normalizedPort: port)
    }

    /// Validates `text` exactly as the TypeScript client does before it sends a token.
    public init(validating text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.range(of: "://") else { throw LuunaOriginError.notHTTPLoopback }
        let scheme = trimmed[..<separator.lowerBound].lowercased()
        let afterScheme = trimmed[separator.upperBound...]
        let authorityEnd = afterScheme.firstIndex { "/?#\\".contains($0) } ?? afterScheme.endIndex
        let authority = afterScheme[..<authorityEnd]
        let remainder = afterScheme[authorityEnd...]

        let hasCredentials = authority.contains("@")
        let hostAndPort = authority.split(separator: "@", omittingEmptySubsequences: false).last ?? ""
        let (hostText, portText) = try Self.split(hostAndPort)
        let port = try Self.port(portText)

        guard scheme == "http", let host = Host(rawValue: hostText.lowercased()) else {
            throw LuunaOriginError.notHTTPLoopback
        }
        guard !hasCredentials, Self.isBare(remainder) else { throw LuunaOriginError.notBareOrigin }
        self.init(host: host, normalizedPort: port)
    }

    private init(host: Host, normalizedPort port: Int?) {
        self.host = host
        self.port = port == 80 ? nil : port
    }

    /// `http://host[:port]`, with no trailing slash, as the TypeScript client's `url.origin`.
    public var description: String {
        "http://\(host.rawValue)" + (port.map { ":\($0)" } ?? "")
    }

    /// Built from validated parts only, so it always parses.
    public var url: URL { URL(string: description)! }

    /// `<origin>/api/v1<path>`. `path` starts with `/` and encodes each variable segment with `pathSegment(_:)`,
    /// so the result always parses.
    public func apiURL(_ path: String) -> URL {
        URL(string: description + "/api/v1" + path)!
    }

    /// `encodeURIComponent` for one path segment: everything but `A–Z a–z 0–9 - _ . ! ~ * ' ( )` is
    /// percent-encoded as UTF-8, so an opaque native ID can never add a segment or a query.
    public static func pathSegment(_ value: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()".utf8)
        return value.utf8.map { allowed.contains($0) ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0) }
            .joined()
    }

    private static func split(_ hostAndPort: Substring) throws -> (host: Substring, port: Substring?) {
        if hostAndPort.hasPrefix("[") {
            guard let close = hostAndPort.firstIndex(of: "]") else { throw LuunaOriginError.malformed }
            let host = hostAndPort[...close]
            let rest = hostAndPort[hostAndPort.index(after: close)...]
            if rest.isEmpty { return (host, nil) }
            guard rest.first == ":" else { throw LuunaOriginError.malformed }
            return (host, rest.dropFirst())
        }
        let parts = hostAndPort.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw LuunaOriginError.malformed }
        return (parts[0], parts.count == 2 ? parts[1] : nil)
    }

    private static func port(_ text: Substring?) throws -> Int? {
        guard let text, !text.isEmpty else { return nil }
        guard text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), value <= 65_535 else {
            throw LuunaOriginError.malformed
        }
        return value
    }

    /// Only `""` or `/`, optionally followed by an empty query and an empty fragment, as `new URL` reports
    /// `search` and `hash` as empty for a bare `?` or `#`.
    private static func isBare(_ remainder: Substring) -> Bool {
        var rest = remainder
        for marker in ["/", "?", "#"] where rest.hasPrefix(marker) {
            rest = rest.dropFirst()
        }
        return rest.isEmpty
    }
}

extension LuunaOrigin: Codable {
    /// Stored as its string form; a stored value that fails validation does not decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        do {
            try self.init(validating: text)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not an HTTP loopback origin: \(error)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
