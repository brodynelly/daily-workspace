import Foundation

/// The system that owns an item. The app shows the owner and never derives one owner's status from another's.
public enum LoopAuthority: String, Codable, CaseIterable, Hashable, Sendable {
    case org
    case seeds
    case plot
    case local
    case reminders
    case luuna
}

/// A date as the owning source wrote it. Org timestamps are wall-clock days with an optional time;
/// Seeds and Plot record exact instants, which are also kept in `instant`.
public struct LoopDate: Hashable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int?
    public let minute: Int?
    /// The exact moment, when the source recorded one (ISO 8601 in Seeds and Plot).
    public let instant: Date?
    /// Org distinguishes active `<…>` from inactive `[…]` timestamps; other sources are always active.
    public let isActive: Bool
    /// The source text, verbatim.
    public let raw: String

    public init(
        year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil, instant: Date? = nil,
        isActive: Bool = true, raw: String
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.instant = instant
        self.isActive = isActive
        self.raw = raw
    }

    /// An exact instant, placed on the calendar day it falls on in `calendar`.
    public init(instant: Date, raw: String, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        self.init(
            year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1, hour: c.hour, minute: c.minute,
            instant: instant, raw: raw)
    }

    public var localDay: LocalDay { LocalDay(year: year, month: month, day: day) }

    public var description: String { raw }
}

/// One item from one owner, with the owner's status verbatim. Built only by that owner's reader.
public struct OpenLoop: Identifiable, Hashable, Sendable {
    public let authority: LoopAuthority
    /// Authority-qualified and opaque, for example `org:<:ID:>` or `seeds:brodynelly-brain-b35c17`.
    public let id: String
    public let title: String
    /// The owner's own kind: `heading` for Org, the Seeds `type` (or `plan`), `plot` for Plot.
    public let kind: String
    /// A project slug, only when the owner states one (the Seeds `project:<slug>` label).
    public let project: String?
    /// Exactly as written by the owner (`NEXT`, `in_progress`, `drafting`…). Never normalized.
    public let nativeStatus: String
    /// True only when the owner's own vocabulary marks the item finished (an Org done keyword,
    /// Seeds `closed`/`done`, Plot `done`/`archived`).
    public let isDoneInSource: Bool
    public let scheduled: LoopDate?
    public let deadline: LoopDate?
    public let closed: LoopDate?
    public let labels: [String]
    /// Vault-relative path of the owning file.
    public let sourcePath: String?
    /// 1-based line in `sourcePath`.
    public let line: Int?
    /// Seeds/Plot `updatedAt`, or a content hash for Org headings.
    public let revision: String?
    public let observedAt: Date

    public init(
        authority: LoopAuthority, nativeID: String, title: String, kind: String, project: String? = nil,
        nativeStatus: String, isDoneInSource: Bool, scheduled: LoopDate? = nil, deadline: LoopDate? = nil,
        closed: LoopDate? = nil, labels: [String] = [], sourcePath: String? = nil, line: Int? = nil,
        revision: String? = nil, observedAt: Date
    ) {
        self.authority = authority
        self.id = Self.qualifiedID(authority, nativeID)
        self.title = title
        self.kind = kind
        self.project = project
        self.nativeStatus = nativeStatus
        self.isDoneInSource = isDoneInSource
        self.scheduled = scheduled
        self.deadline = deadline
        self.closed = closed
        self.labels = labels
        self.sourcePath = sourcePath
        self.line = line
        self.revision = revision
        self.observedAt = observedAt
    }

    public static func qualifiedID(_ authority: LoopAuthority, _ nativeID: String) -> String {
        "\(authority.rawValue):\(nativeID)"
    }
}

/// One problem found while reading a source. `path` is vault-relative; `line` is 1-based.
public struct SourceIssue: Hashable, Sendable, CustomStringConvertible {
    public let path: String?
    public let line: Int?
    public let message: String

    public init(path: String? = nil, line: Int? = nil, message: String) {
        self.path = path
        self.line = line
        self.message = message
    }

    public var description: String {
        switch (path, line) {
        case (let path?, let line?): return "\(path):\(line): \(message)"
        case (let path?, nil): return "\(path): \(message)"
        default: return message
        }
    }
}

/// Distinct, reportable states. An inaccessible source is never "nothing to do".
public enum SourceState: Hashable, Sendable {
    /// The app has no reader for this source on this system.
    case unsupported
    /// The OS or the file system denied access.
    case unauthorized
    /// The source should exist but could not be read (missing folder or file, I/O error).
    case unavailable(reason: String)
    /// The owner's store has not been set up (for example no `.seeds/`).
    case uninitialized
    /// The app declined to read it (outside the vault, excluded by policy).
    case refused(reason: String)
    /// Read, but some records or files could not be used.
    case partial(issues: [SourceIssue])
    /// Read completely; it holds nothing.
    case empty
    /// Read completely; it holds items.
    case populated

    /// True when this observation reflects the source's current content (fully or partially).
    public var isReadable: Bool {
        switch self {
        case .partial, .empty, .populated: return true
        default: return false
        }
    }

    public var issues: [SourceIssue] {
        if case .partial(let issues) = self { return issues }
        return []
    }

    /// `.populated`/`.empty` from a count, or `.partial` when there were issues.
    public static func readable(count: Int, issues: [SourceIssue]) -> SourceState {
        if !issues.isEmpty { return .partial(issues: issues) }
        return count == 0 ? .empty : .populated
    }
}

/// The result of reading one source at one moment.
public struct SourceObservation<Value> {
    public var state: SourceState
    /// What this read produced. After `following(_:)`, a failed read carries the previous value (stale).
    public var value: Value
    public var observedAt: Date
    /// The most recent moment this source was read successfully. Kept across failures.
    public var lastSuccessAt: Date?

    public init(state: SourceState, value: Value, observedAt: Date, lastSuccessAt: Date? = nil) {
        self.state = state
        self.value = value
        self.observedAt = observedAt
        self.lastSuccessAt = lastSuccessAt ?? (state.isReadable ? observedAt : nil)
    }

    /// This observation as the successor of `previous` from the **same** source (same vault, same path).
    /// A readable result stands on its own. A failed one keeps the failure state but carries the previous
    /// value and `lastSuccessAt`, so the UI can show the last good data as stale instead of as empty.
    public func following(_ previous: SourceObservation<Value>?) -> SourceObservation<Value> {
        guard !state.isReadable, let previous else { return self }
        return SourceObservation(
            state: state, value: previous.value, observedAt: observedAt, lastSuccessAt: previous.lastSuccessAt)
    }

    public func map<T>(_ transform: (Value) -> T) -> SourceObservation<T> {
        SourceObservation<T>(
            state: state, value: transform(value), observedAt: observedAt, lastSuccessAt: lastSuccessAt)
    }
}

extension SourceObservation: Equatable where Value: Equatable {}
extension SourceObservation: Sendable where Value: Sendable {}

/// A read-only owner of open loops.
public protocol OpenLoopSource: Sendable {
    var authority: LoopAuthority { get }
    func readLoops(now: Date) -> SourceObservation<[OpenLoop]>
}

/// Maps file-system errors to source states.
enum SourceFailure {
    static func state(for error: Error, missing: SourceState) -> SourceState {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoPermissionError: return .unauthorized
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return missing
            default: break
            }
        }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EACCES) || ns.code == Int(EPERM) { return .unauthorized }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOENT) { return missing }
        return .unavailable(reason: ns.localizedDescription)
    }

    /// Hex FNV-1a of `data`, used as a content revision.
    static func hash(_ data: Data) -> String {
        String(FileSnapshot(data: data, modified: nil).fingerprint, radix: 16)
    }
}

/// Reads one vault-relative file for an external-source reader. Rejects anything that resolves outside the
/// vault, symlinks included, before touching the file.
enum SourceFile {
    enum Outcome {
        case data(Data)
        case failed(SourceState)
    }

    static func read(_ relativePath: String, in vault: NoteVault) -> Outcome {
        let url: URL
        do { url = try vault.resolve(relativePath: relativePath) } catch {
            return .failed(.refused(reason: "\(relativePath) resolves outside the vault"))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failed(.unavailable(reason: "\(relativePath) was not found"))
        }
        guard !isDirectory.boolValue else { return .failed(.unavailable(reason: "\(relativePath) is a folder")) }
        do { return .data(try Data(contentsOf: url)) } catch {
            return .failed(
                SourceFailure.state(for: error, missing: .unavailable(reason: "\(relativePath) was not found")))
        }
    }

    /// Splits text into lines, dropping a trailing `\r` from each.
    static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.hasSuffix("\r") ? $0.dropLast() : $0
        }
    }
}
