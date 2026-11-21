import Foundation
import os

/// Removing a server's Scout: its key can't sign in again, and the sessions it has end at once.
struct ScoutRemovalWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Scouts")

    let scouts: ScoutStore
    let sessions: SessionStore
    let now: @Sendable () -> Date

    /// Returns false when the server has no Scout.
    func remove(forServer serverID: UUID, by deviceID: UUID) throws -> Bool {
        guard try scouts.remove(forServer: serverID, by: deviceID, at: now()) else { return false }
        sessions.endScoutSessions(forServer: serverID)
        Self.logger.notice("Removed a server's Scout")
        return true
    }
}
