import AppKit
import DailyCore
import Foundation

/// The only data crossing the Apple Events boundary: Mail message metadata, never bodies or headers.
/// Rows are [message ID, subject, native status]. Source failures carry no Mail account or subject text.
enum MailReadResult: Sendable {
    case unsupported
    case unauthorized
    case unavailable
    case data(rows: [[String]], incomplete: Bool)
}

protocol MailResponseSource: Sendable {
    func read() -> MailReadResult
}

/// Revocable permission for a queued Mail read. A read already entering its source is in flight;
/// revocation prevents work that has not yet reached that boundary without waiting for Mail.app.
final class MailReadAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    func revoke() { lock.withLock { active = false } }
    var isActive: Bool { lock.withLock { active } }
}

/// Explicit opt-in is required before even asking the OS for Mail Automation permission.
/// This source is deliberately not registered with Assistant tools or the general vault readers.
struct MailOpenLoopReader: OpenLoopSource {
    let authority: LoopAuthority = .mail
    private let enabled: Bool
    private let responseSource: any MailResponseSource

    init(enabled: Bool = false, responseSource: any MailResponseSource = AppleEventsMailResponseSource()) {
        self.enabled = enabled
        self.responseSource = responseSource
    }

    func readLoops(now: Date) -> SourceObservation<[OpenLoop]> {
        readLoops(now: now, authorization: nil)
    }

    func readLoops(now: Date, authorization: MailReadAuthorization?) -> SourceObservation<[OpenLoop]> {
        guard enabled, !Task.isCancelled, authorization?.isActive ?? true else {
            return SourceObservation(state: .unauthorized, value: [], observedAt: now)
        }
        let result = responseSource.read()
        switch result {
        case .unsupported:
            return SourceObservation(state: .unsupported, value: [], observedAt: now)
        case .unauthorized:
            return SourceObservation(state: .unauthorized, value: [], observedAt: now)
        case .unavailable:
            return SourceObservation(
                state: .unavailable(reason: "Mail could not be read."), value: [], observedAt: now)
        case .data(let rows, let incomplete):
            var loops: [OpenLoop] = []
            var seen = Set<String>()
            var issues: [SourceIssue] = []
            if incomplete || rows.count > Self.maximumRows {
                issues.append(SourceIssue(message: "Mail returned a limited or incomplete read."))
            }
            for row in rows.prefix(Self.maximumRows) {
                guard row.count == 3,
                    !row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    row[0].utf8.count <= Self.maximumFieldBytes,
                    !row[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    row[1].utf8.count <= Self.maximumFieldBytes,
                    Self.nativeStatuses.contains(row[2])
                else {
                    if !issues.contains(SourceIssue(message: "Mail returned invalid message metadata.")) {
                        issues.append(SourceIssue(message: "Mail returned invalid message metadata."))
                    }
                    continue
                }
                guard seen.insert(row[0]).inserted else { continue }
                loops.append(
                    OpenLoop(
                        authority: .mail, nativeID: row[0], title: row[1], kind: "message",
                        nativeStatus: row[2], isDoneInSource: false, observedAt: now))
            }
            return SourceObservation(
                state: .readable(count: loops.count, issues: issues), value: loops, observedAt: now)
        }
    }

    static let maximumRows = 100
    static let maximumFieldBytes = 512
    static let nativeStatuses: Set<String> = ["flagged status: true", "read status: false"]
}

/// A fixed AppleScript, executed only after opt-in. Never interpolates user input, reads message bodies,
/// logs a title/account, or invokes the network directly. Mail.app remains the owner of message state.
private struct AppleEventsMailResponseSource: MailResponseSource {
    func read() -> MailReadResult {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") != nil,
            let script = NSAppleScript(source: Self.script)
        else { return .unsupported }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil {
            let code = error?[NSAppleScript.errorNumber] as? Int
            return code == -1743 ? .unauthorized : .unavailable
        }
        guard result.numberOfItems == 3,
            let rows = result.atIndex(1), let incomplete = result.atIndex(2),
            let hasAccounts = result.atIndex(3), hasAccounts.booleanValue
        else { return .unavailable }
        var parsed: [[String]] = []
        var malformed = false
        let limit = min(rows.numberOfItems, MailOpenLoopReader.maximumRows + 1)
        if limit > 0 {
            for index in 1...limit {
                guard let row = rows.atIndex(index), row.numberOfItems == 3,
                    let identifier = row.atIndex(1)?.stringValue,
                    let subject = row.atIndex(2)?.stringValue,
                    let status = row.atIndex(3)?.stringValue
                else {
                    malformed = true
                    continue
                }
                parsed.append([identifier, subject, status])
            }
        }
        return .data(rows: parsed, incomplete: incomplete.booleanValue || malformed || rows.numberOfItems > limit)
    }

    private static let script = """
        set resultRows to {}
        set incomplete to false
        set pending to {}
        tell application id "com.apple.mail"
            if (count of accounts) is 0 then return {resultRows, false, false}
            repeat with mailAccount in accounts
                try
                    set pending to pending & (every mailbox of mailAccount)
                on error
                    set incomplete to true
                end try
            end repeat
            set scannedMailboxes to 0
            repeat while (count of pending) > 0
                if scannedMailboxes >= 200 or (count of resultRows) >= 100 then
                    set incomplete to true
                    exit repeat
                end if
                set currentMailbox to item 1 of pending
                set pending to rest of pending
                set scannedMailboxes to scannedMailboxes + 1
                try
                    set pending to pending & (every mailbox of currentMailbox)
                    set flaggedMessages to (every message of currentMailbox whose flagged status is true)
                    repeat with mailMessage in flaggedMessages
                        if (count of resultRows) >= 100 then
                            set incomplete to true
                            exit repeat
                        end if
                        try
                            set messageID to message id of mailMessage as text
                            set messageSubject to subject of mailMessage as text
                            if (length of messageID) <= 512 and (length of messageSubject) <= 512 then
                                set end of resultRows to {messageID, messageSubject, "flagged status: true"}
                            else
                                set incomplete to true
                            end if
                        on error
                            set incomplete to true
                        end try
                    end repeat
                    if (name of currentMailbox as text) is "Important" then
                        set unreadMessages to (every message of currentMailbox whose read status is false)
                        repeat with mailMessage in unreadMessages
                            if (count of resultRows) >= 100 then
                                set incomplete to true
                                exit repeat
                            end if
                            try
                                set messageID to message id of mailMessage as text
                                set messageSubject to subject of mailMessage as text
                                if (length of messageID) <= 512 and (length of messageSubject) <= 512 then
                                    set end of resultRows to {messageID, messageSubject, "read status: false"}
                                else
                                    set incomplete to true
                                end if
                            on error
                                set incomplete to true
                            end try
                        end repeat
                    end if
                on error
                    set incomplete to true
                end try
            end repeat
        end tell
        return {resultRows, incomplete, true}
        """
}
