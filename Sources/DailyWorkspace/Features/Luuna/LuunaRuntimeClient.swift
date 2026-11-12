import DailyCore
import Foundation
import OSLog

extension Log {
    static let luuna = Logger(subsystem: subsystem, category: "luuna")
}

extension KeychainAPIKeyStore {
    /// The Keychain service holding the Luuna runtime's bearer token. The token is never written to a file.
    static let luunaService = "app.dailyworkspace.luuna"
    static var luuna: KeychainAPIKeyStore { KeychainAPIKeyStore(service: luunaService) }
}

extension LuunaOriginError: LocalizedError {
    /// The TypeScript client's sentences for the same refusals.
    public var errorDescription: String? {
        switch self {
        case .malformed: return "That is not a valid runtime URL."
        case .notHTTPLoopback: return "Use an HTTP loopback runtime URL (127.0.0.1, localhost or [::1])."
        case .notBareOrigin: return "Runtime URL must contain only a loopback address and optional port."
        }
    }
}

/// The origin and bearer token of one connection session. The token never appears in descriptions or mirrors,
/// so it cannot reach a log line or a test failure message.
struct LuunaConnection: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    let origin: LuunaOrigin
    let token: String

    var description: String { "LuunaConnection(\(origin), token: <redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["origin": origin]) }
}

/// Read-only access to an already running Luuna runtime: the first certified profile (health, project list,
/// project detail, component status). Every method is one GET. Nothing here starts, initializes, discovers,
/// enables or changes anything. Methods throw `LuunaReadFailure`, or `CancellationError` when cancelled.
protocol LuunaRuntimeReading: Sendable {
    func health(_ connection: LuunaConnection) async throws -> LuunaHealth
    func projects(_ connection: LuunaConnection) async throws -> [LuunaProjectRecord]
    func project(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaProjectView
    func components(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaComponentStatus
}

/// Paths under `<origin>/api/v1`, as `LuunaClient` builds them in `packages/api-client/src/index.ts`.
enum LuunaEndpoint {
    static let health = "/health"
    static let projects = "/projects"
    static func project(_ id: String) -> String { "/projects/" + LuunaOrigin.pathSegment(id) }
    static func components(_ id: String) -> String { project(id) + "/components" }
}

/// `LuunaRuntimeReading` over `URLSession`, with the TypeScript client's transport: loopback origins only (checked
/// by `LuunaOrigin`), `Authorization: Bearer`, `Accept: application/json`, no HTTP cache (`no-store`), no ambient
/// cookies or credentials (`credentials: "omit"`), and every redirect refused (`redirect: "error"`).
final class LuunaRuntimeClient: LuunaRuntimeReading {
    static let requestTimeout: TimeInterval = 10

    private let session: URLSession

    /// `protocolClasses` exists for tests (a `URLProtocol` stub); production passes nil.
    init(protocolClasses: [AnyClass]? = nil) {
        session = URLSession(
            configuration: Self.configuration(protocolClasses: protocolClasses),
            delegate: LuunaRedirectGuard(), delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// The session configuration in use (a copy).
    var configuration: URLSessionConfiguration { session.configuration }

    static func configuration(protocolClasses: [AnyClass]?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout * 3
        configuration.waitsForConnectivity = false
        // The token is for this Mac only: never route a loopback request through a configured proxy.
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
            kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false,
        ]
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return configuration
    }

    func health(_ connection: LuunaConnection) async throws -> LuunaHealth {
        try await get(LuunaEndpoint.health, connection)
    }

    func projects(_ connection: LuunaConnection) async throws -> [LuunaProjectRecord] {
        try await get(LuunaEndpoint.projects, connection)
    }

    func project(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaProjectView {
        try await get(LuunaEndpoint.project(projectID), connection)
    }

    func components(_ projectID: String, _ connection: LuunaConnection) async throws -> LuunaComponentStatus {
        try await get(LuunaEndpoint.components(projectID), connection)
    }

    /// The request every read sends. Exposed for tests.
    static func request(_ path: String, _ connection: LuunaConnection) -> URLRequest {
        var request = URLRequest(
            url: connection.origin.apiURL(path), cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func get<Value: Decodable>(_ path: String, _ connection: LuunaConnection) async throws -> Value {
        let (data, response) = try await send(Self.request(path, connection))
        guard let http = response as? HTTPURLResponse else { throw LuunaReadFailure.unsupported }
        if let failure = LuunaReadFailure.classify(status: http.statusCode, body: data) { throw failure }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw LuunaReadFailure.undecodable
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw Self.failure(for: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LuunaReadFailure.unavailable(.transport(code: (error as NSError).code))
        }
    }

    /// Maps a transport failure. Nothing from the error's text is kept.
    static func failure(for error: URLError) -> Error {
        switch error.code {
        case .cancelled:
            return CancellationError()
        case .timedOut:
            return LuunaReadFailure.unavailable(.timedOut)
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed:
            return LuunaReadFailure.unavailable(.cannotConnect)
        case .httpTooManyRedirects, .redirectToNonExistentLocation:
            return LuunaReadFailure.unavailable(.redirectRefused)
        default:
            return LuunaReadFailure.unavailable(.transport(code: error.code.rawValue))
        }
    }
}

/// Refuses every redirect: the 3xx response itself completes the task, and `LuunaReadFailure.classify` turns it
/// into `.unavailable(.redirectRefused)`. The token is never sent to a redirect target.
final class LuunaRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        Log.luuna.notice("Refused a redirect from the Luuna runtime (HTTP \(response.statusCode, privacy: .public))")
        completionHandler(nil)
    }
}
