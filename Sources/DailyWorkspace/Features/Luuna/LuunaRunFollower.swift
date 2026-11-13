import Combine
import DailyCore
import Foundation

protocol LuunaRunFollowing: Sendable {
    func follow(
        _ runID: String, after sequence: Int, _ connection: LuunaConnection,
        onChunk: @escaping @Sendable (Data) -> Void
    ) async throws
}

extension LuunaCLIReader: LuunaRunFollowing {}

/// A selected run's read-only event stream. The runner bounds each connection and kills its process
/// group on cancellation; after a broken connection, resume only after the last complete sequence.
@MainActor
final class LuunaRunFollower: ObservableObject {
    @Published private(set) var events = LuunaObservation<[LuunaRunEvent]>()
    @Published private(set) var isFollowing = false
    private(set) var cursor = 0

    private let reader: any LuunaRunFollowing
    private var decoder = LuunaRunEventStream()
    private var task: Task<Void, Never>?
    private var generation = 0
    private var pendingBytes = 0
    private var retainedBytes = 0
    private var retainedBatches: [(count: Int, bytes: Int)] = []

    init(reader: any LuunaRunFollowing = LuunaCLIReader()) { self.reader = reader }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        isFollowing = false
        cursor = 0
        decoder = LuunaRunEventStream()
        pendingBytes = 0
        retainedBytes = 0
        retainedBatches.removeAll()
        events = LuunaObservation()
    }

    func start(runID: String, projectID: String, connection: LuunaConnection) {
        stop()
        let generation = generation
        isFollowing = true
        task = Task { [weak self] in
            guard let self else { return }
            var failures = 0
            while !Task.isCancelled, generation == self.generation {
                let permit = DispatchSemaphore(value: 0)
                let previousCursor = decoder.cursor
                do {
                    try await reader.follow(runID, after: decoder.cursor, connection) { [weak self] chunk in
                        Task { @MainActor in
                            defer { permit.signal() }
                            self?.receive(chunk, runID: runID, projectID: projectID, generation: generation)
                        }
                        permit.wait()
                    }
                    guard generation == self.generation, !Task.isCancelled else { return }
                    finishConnection()
                    return
                } catch is CancellationError {
                    return
                } catch let failure as LuunaReadFailure {
                    guard generation == self.generation, !Task.isCancelled else { return }
                    if decoder.cursor > previousCursor { failures = 0 }
                    if shouldRetry(failure, attempt: failures), events.state != .partial {
                        failures += 1
                        _ = decoder.finish()
                        pendingBytes = 0
                        try? await Task.sleep(for: .milliseconds(400))
                        continue
                    }
                    fail(failure)
                    return
                } catch {
                    guard generation == self.generation, !Task.isCancelled else { return }
                    fail(.unavailable(.cannotConnect))
                    return
                }
            }
        }
    }

    private func shouldRetry(_ failure: LuunaReadFailure, attempt: Int) -> Bool {
        guard case .unavailable(let reason) = failure else { return false }
        if reason == .timedOut { return events.value != nil || attempt < 3 }
        return reason == .cannotConnect && attempt < 3
    }

    private func fail(_ failure: LuunaReadFailure) {
        if case .unavailable = failure, events.state == .partial {
            isFollowing = false
            return
        }
        events.recordFailure(failure.state, at: Date())
        isFollowing = false
    }

    private func finishConnection() {
        if decoder.finish() != nil { events.recordFailure(.partial, at: Date()) }
        pendingBytes = 0
        if events.state == .unavailable(.notChecked) {
            events.recordSuccess([], state: .empty, at: Date())
        }
        isFollowing = false
    }

    private func receive(_ chunk: Data, runID: String, projectID: String, generation: Int) {
        guard generation == self.generation, isFollowing else { return }
        pendingBytes += chunk.count
        let parsed = decoder.append(chunk)
        if !parsed.invalidLines.isEmpty {
            // Let the CLI exit so its fixed error shape can classify a 401/403 correctly.
            events.recordFailure(.partial, at: Date())
            isFollowing = false
            return
        }
        guard
            parsed.events.allSatisfy({
                $0.fields["run_id"]?.stringValue == runID && $0.fields["project_id"]?.stringValue == projectID
            })
        else {
            events.recordFailure(.partial, at: Date())
            isFollowing = false
            task?.cancel()
            return
        }
        guard !parsed.events.isEmpty else { return }
        cursor = decoder.cursor
        retain(parsed.events)
    }

    private func retain(_ incoming: [LuunaRunEvent]) {
        var visible = events.value ?? []
        if incoming.count >= 500 {
            visible = Array(incoming.suffix(500))
            retainedBatches.removeAll()
            retainedBytes = 0
        } else {
            visible.append(contentsOf: incoming)
        }
        retainedBatches.append((min(incoming.count, 500), pendingBytes))
        retainedBytes += pendingBytes
        pendingBytes = 0
        while retainedBatches.count > 1 && (visible.count > 500 || retainedBytes > 2 * 1024 * 1024) {
            let first = retainedBatches.removeFirst()
            visible.removeFirst(first.count)
            retainedBytes -= first.bytes
        }
        events.recordSuccess(visible, at: Date())
    }
}
