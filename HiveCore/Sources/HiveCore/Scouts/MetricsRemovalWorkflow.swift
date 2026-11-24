import Foundation
import os

/// Removing a server's metrics: its Scout's key can't sign in again, the sessions it has end at once,
/// and a restored server stops waiting for its Scout. The figures already kept stay until they age out.
struct MetricsRemovalWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Scouts")

    let scouts: ScoutStore
    let sessions: SessionStore
    let now: @Sendable () -> Date

    /// Returns false when the server has no metrics.
    func remove(forServer serverID: UUID, by deviceID: UUID) throws -> Bool {
        guard try scouts.removeMetrics(forServer: serverID, by: deviceID, at: now()) else { return false }
        sessions.endScoutSessions(forServer: serverID)
        Self.logger.notice("Removed a server's metrics")
        return true
    }
}
