import DailyCore
import Foundation

/// How a recorded source compares with the file on disk now.
enum SourceCheck: Equatable, Sendable {
    case unchanged
    /// The file's bytes differ from what was read when the record was accepted.
    case changed
    /// The file is no longer in the vault.
    case missing
    /// The path can't be read now (refused by the vault policy, or an I/O error), with why.
    case unreadable(String)
}

/// The latest accepted restart record for a project, with each source checked against the disk.
struct LatestRestart: Equatable, Sendable {
    var record: RestartRecord?
    var checks: [String: SourceCheck]
    /// 1-based ledger lines that could not be read. They are reported, never repaired.
    var skippedLines: [Int]
}

/// Accepts reviewed restart drafts into the `RestartLedger` and reads them back. Only vault-resolved paths are
/// hashed; nothing in the vault is ever written. Synchronous and file-bound: call it off the main actor.
struct RestartRecorder: Sendable {
    let ledger: RestartLedger
    let vaultRoot: URL?
    var scope: VaultScope = .standard

    /// The draft as an accepted record, with every source hashed as it is on disk now, appended to the ledger.
    /// Throws (and appends nothing) when a source can't be hashed. Returns the record and the ledger lines that
    /// could not be read when it was read back.
    func accept(_ draft: RestartDraft, at date: Date) throws -> (record: RestartRecord, skippedLines: [Int]) {
        let sources = try sourceRefs(for: draft.sources.map(\.path), at: date)
        let record = draft.accepted(at: date, sources: sources)
        try ledger.append(record)
        let skipped = (try? ledger.records(project: record.projectSlug).skippedLines) ?? []
        return (record, skipped)
    }

    /// Each path resolved in the vault and hashed now. Throws naming every path that couldn't be.
    func sourceRefs(for paths: [String], at date: Date) throws -> [SourceRef] {
        var refs: [SourceRef] = []
        var failures: [String] = []
        for path in paths {
            switch hash(path) {
            case .success((let relative, let sha)):
                refs.append(SourceRef(path: relative, sha256: sha, observedAt: date))
            case .failure(let failure): failures.append(failure.message)
            }
        }
        guard failures.isEmpty else {
            throw ToolFailure(
                "Nothing was saved. Remove these sources or try again: " + failures.joined(separator: " "))
        }
        return refs
    }

    /// The newest accepted record for `project` and how each of its sources compares with the disk.
    func latest(project: String) throws -> LatestRestart {
        let read = try ledger.records(project: project)
        guard let record = read.latest else {
            return LatestRestart(record: nil, checks: [:], skippedLines: read.skippedLines)
        }
        var checks: [String: SourceCheck] = [:]
        for source in record.sources { checks[source.path] = check(source) }
        return LatestRestart(record: record, checks: checks, skippedLines: read.skippedLines)
    }

    func check(_ source: SourceRef) -> SourceCheck {
        guard let vaultRoot else { return .unreadable("No vault is chosen.") }
        let allowed: VaultReadPolicy.Allowed
        do {
            allowed = try VaultReadPolicy.resolve(source.path, root: vaultRoot, scope: scope)
        } catch {
            return .unreadable((error as? ToolFailure)?.message ?? "It can't be read.")
        }
        guard FileManager.default.fileExists(atPath: allowed.url.path) else { return .missing }
        guard let sha = try? RestartLedger.sha256(ofFileAt: allowed.url) else {
            return .unreadable("It could not be read.")
        }
        return sha == source.sha256 ? .unchanged : .changed
    }

    private func hash(_ path: String) -> Result<(String, String), ToolFailure> {
        guard let vaultRoot else { return .failure(ToolFailure("No vault is chosen, so \(path) can't be hashed.")) }
        do {
            let allowed = try VaultReadPolicy.resolve(path, root: vaultRoot, scope: scope)
            guard FileManager.default.fileExists(atPath: allowed.url.path) else {
                return .failure(ToolFailure("\(allowed.path) is not in the vault."))
            }
            return .success((allowed.path, try RestartLedger.sha256(ofFileAt: allowed.url)))
        } catch let failure as ToolFailure {
            return .failure(failure)
        } catch {
            return .failure(ToolFailure("\(path) could not be read."))
        }
    }
}

/// The restart ledger for the UI: accepts drafts off the main actor and tells views when to re-read.
@MainActor
final class RestartRecords: ObservableObject {
    enum Acceptance: Equatable {
        /// Appended. `skippedLines` are ledger lines that could not be read back.
        case saved(RestartRecord, skippedLines: [Int])
        case failed(String)
    }

    /// Bumped after every successful append, so panels re-read.
    @Published private(set) var revision = 0

    let ledger: RestartLedger
    private let vaultRoot: () -> URL?
    private let now: () -> Date

    init(ledger: RestartLedger, vaultRoot: @escaping () -> URL?, now: @escaping () -> Date = Date.init) {
        self.ledger = ledger
        self.vaultRoot = vaultRoot
        self.now = now
    }

    var recorder: RestartRecorder { RestartRecorder(ledger: ledger, vaultRoot: vaultRoot()) }

    /// Hash the sources, then append. Returns `.saved` only after the append returned.
    func accept(_ draft: RestartDraft) async -> Acceptance {
        let recorder = recorder
        let date = now()
        do {
            let saved = try await Task.detached(priority: .userInitiated) {
                try recorder.accept(draft, at: date)
            }.value
            revision += 1
            Log.app.info("Appended a restart record to the ledger")
            return .saved(saved.record, skippedLines: saved.skippedLines)
        } catch let failure as ToolFailure {
            return .failed(failure.message)
        } catch {
            Log.app.error("Restart record could not be appended: \(Log.code(error), privacy: .public)")
            return .failed("The restart record could not be saved: \(error.localizedDescription)")
        }
    }

    /// The latest record for `project`, with its sources checked against the disk off the main actor.
    func latest(project: String) async -> Result<LatestRestart, ToolFailure> {
        let recorder = recorder
        do {
            return .success(
                try await Task.detached(priority: .userInitiated) { try recorder.latest(project: project) }.value)
        } catch {
            Log.app.error("Restart ledger could not be read: \(Log.code(error), privacy: .public)")
            return .failure(ToolFailure("The restart ledger could not be read: \(error.localizedDescription)"))
        }
    }
}
