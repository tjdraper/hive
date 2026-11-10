import Foundation
import HiveKit
import ServiceLifecycle

/// One device's live updates: where every job stands, then each change as it happens, until the
/// device's session runs out or ends, or Hive stops.
struct LiveUpdateStream: Sendable {
    enum Ending: String {
        case sessionEnded
        case hiveStopping
    }

    private enum Signal {
        case event(RunEvent)
        case heartbeat
    }

    let events: RunEventBroadcaster
    let statuses: JobStatusReader
    let heartbeat: Duration
    /// Checked before every line, so nothing reaches a device once its session has ended.
    let isSignedIn: @Sendable () -> Bool

    /// Throws when a line can't be written, such as once the device has gone.
    func run(writing write: (LiveUpdate) async throws -> Void) async throws -> Ending {
        // Listening before the statuses are read, so nothing that happens between is missed. Events that
        // arrive meanwhile repeat what the statuses show, which leaves them as they were.
        let events = events.listen()
        guard isSignedIn() else { return .sessionEnded }
        try await write(.jobStatuses(statuses.statuses()))

        let (signals, input) = AsyncStream.makeStream(of: Signal.self)
        return try await withThrowingTaskGroup { group in
            group.addTask {
                for await event in events {
                    input.yield(.event(event))
                }
            }
            group.addTask { [heartbeat] in
                while true {
                    try await Task.sleep(for: heartbeat)
                    input.yield(.heartbeat)
                }
            }
            defer { group.cancelAll() }

            for await signal in signals.cancelOnGracefulShutdown() {
                guard isSignedIn() else { return .sessionEnded }
                switch signal {
                case .heartbeat:
                    try await write(.heartbeat)
                case .event(let event):
                    try await write(.event(event))
                    if let jobID = event.changedJobState, let status = try await statuses.statuses(ofJob: jobID).first {
                        try await write(.jobStatus(status))
                    }
                }
            }
            return .hiveStopping
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
