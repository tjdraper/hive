import Foundation

/// One line of `HiveEndpoint.liveUpdates`, each a JSON value of its own.
public enum LiveUpdate: Codable, Hashable, Sendable {
    /// First, once connected: where every job stands, for what follows to update.
    case jobStatuses([JobStatus])
    /// A job's status after it was queued, left the queue, started or finished.
    case jobStatus(JobStatus)
    case event(RunEvent)
    /// After every job's status, once connected, then whenever the recovery key changes or a recovery
    /// file is written.
    case recovery(RecoveryKeyState)
    /// After the recovery key's state, once connected, then whenever the port or the address options
    /// change. A device connected when the port changes keeps this response on the old port, so it
    /// hears of the new one.
    case addresses(HiveAddresses)
    /// Sent while nothing else is, so neither end takes a quiet connection for a dead one.
    case heartbeat
}
