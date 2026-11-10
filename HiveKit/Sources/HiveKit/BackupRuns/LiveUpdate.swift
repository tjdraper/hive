import Foundation

/// One line of `HiveEndpoint.liveUpdates`, each a JSON value of its own.
public enum LiveUpdate: Codable, Hashable, Sendable {
    /// First, once connected: where every job stands, for what follows to update.
    case jobStatuses([JobStatus])
    /// A job's status after it was queued, left the queue, started or finished.
    case jobStatus(JobStatus)
    case event(RunEvent)
    /// Sent while nothing else is, so neither end takes a quiet connection for a dead one.
    case heartbeat
}
