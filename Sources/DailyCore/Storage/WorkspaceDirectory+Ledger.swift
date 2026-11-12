import Foundation

extension WorkspaceDirectory {
    /// Accepted restart records, one JSON object per line (`RestartLedger`). Append-only.
    public var restartLedgerURL: URL { url.appendingPathComponent("restart-ledger.jsonl") }
}
