import Foundation
import HiveKit
import ServiceLifecycle

/// One device's live updates: where every job stands, the recovery key's state and where devices reach
/// the Hive, then each change as it happens, until the device's session runs out or ends, or Hive stops.
/// Servers' figures come from `metrics`, never queued, so a device that falls behind gets each server's
/// newest and still every job event.
struct LiveUpdateStream: Sendable {
    enum Ending: String {
        case sessionEnded
        case hiveStopping
    }

    private enum Signal {
        /// Written as it is.
        case update(LiveUpdate)
        /// Written, followed by the job's new status when it changed one.
        case event(RunEvent)
        /// Each server's newest figures since the last are written.
        case metrics
    }

    let events: Broadcaster<RunEvent>
    let statuses: JobStatusReader
    let recovery: RecoveryKeyWorkflow
    let settings: HiveSettingsStore
    let addressChanges: Broadcaster<HiveAddresses>
    let metrics: MetricsLiveBoard
    let heartbeat: Duration

    /// What one device's stream listens to, from before it reads where things stand.
    private struct Listening {
        let events: AsyncStream<RunEvent>
        let recoveryChanges: AsyncStream<RecoveryKeyState>
        let addressChanges: AsyncStream<HiveAddresses>
        let metricsChanges: AsyncStream<Void>
        /// Told each time a `.metrics` signal is taken, so at most one waits at a time.
        let metricsTaken: AsyncStream<Void>
        let heartbeat: Duration

        func feed(_ input: AsyncStream<Signal>.Continuation, in group: inout ThrowingTaskGroup<Void, any Error>) {
            group.addTask {
                for await event in events {
                    input.yield(.event(event))
                }
            }
            group.addTask {
                for await state in recoveryChanges {
                    input.yield(.update(.recovery(state)))
                }
            }
            group.addTask {
                for await addresses in addressChanges {
                    input.yield(.update(.addresses(addresses)))
                }
            }
            group.addTask {
                var taken = metricsTaken.makeAsyncIterator()
                for await _ in metricsChanges {
                    input.yield(.metrics)
                    guard await taken.next() != nil else { return }
                }
            }
            group.addTask {
                while true {
                    try await Task.sleep(for: heartbeat)
                    input.yield(.update(.heartbeat))
                }
            }
        }
    }

    /// `isSignedIn` is checked before every line, so nothing reaches a device once its session has
    /// ended. Throws when a line can't be written, such as once the device has gone.
    func run(isSignedIn: () -> Bool, writing write: (LiveUpdate) async throws -> Void) async throws -> Ending {
        // Listening before the statuses are read, so nothing that happens between is missed. Events that
        // arrive meanwhile repeat what the statuses show, which leaves them as they were.
        let (metricsChanges, metricsAtStart) = metrics.listen()
        let (metricsTaken, metricsTakenInput) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let listening = Listening(
            events: events.listen(),
            recoveryChanges: recovery.files.changes.listen(),
            addressChanges: addressChanges.listen(),
            metricsChanges: metricsChanges,
            metricsTaken: metricsTaken,
            heartbeat: heartbeat
        )
        var metricsSeen = metricsAtStart
        guard isSignedIn() else { return .sessionEnded }
        try await write(.jobStatuses(statuses.statuses()))
        try await write(.recovery(recovery.state()))
        try await write(.addresses(settings.settings().addresses))

        let (signals, input) = AsyncStream.makeStream(of: Signal.self)
        return try await withThrowingTaskGroup { group in
            listening.feed(input, in: &group)
            defer { group.cancelAll() }

            for await signal in signals.cancelOnGracefulShutdown() {
                guard isSignedIn() else { return .sessionEnded }
                if case .metrics = signal { metricsTakenInput.yield() }
                try await self.write(signal, metricsSeen: &metricsSeen, writing: write)
            }
            return .hiveStopping
        }
    }

    private func write(_ signal: Signal, metricsSeen: inout [UUID: Int], writing write: (LiveUpdate) async throws -> Void) async throws {
        switch signal {
        case .update(let update):
            try await write(update)
        case .metrics:
            for latest in metrics.changes(since: &metricsSeen) {
                try await write(.serverMetrics(latest))
            }
        case .event(let event):
            try await write(.event(event))
            if let jobID = event.changedJobState, let status = try await statuses.statuses(ofJob: jobID).first {
                try await write(.jobStatus(status))
            }
        }
    }
}

private extension RunEvent {
    /// The job whose state the event changed, which the device gets the new status of.
    var changedJobState: UUID? {
        switch self {
        case .queued(let jobID, _), .leftQueue(let jobID): jobID
        case .started(let entry), .finished(let entry): entry.run.jobID
        case .step, .progress, .removed: nil
        }
    }
}
