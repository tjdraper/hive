import Foundation
import os

/// Revoking a device: its key can't sign in again, and the sessions it has end at once.
struct DeviceRevocationWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Devices")

    let devices: DeviceStore
    let sessions: SessionStore
    let now: @Sendable () -> Date

    /// Returns false when there's no device with that ID.
    func revoke(_ deviceID: UUID, by revokingDeviceID: UUID) throws -> Bool {
        guard try devices.remove(id: deviceID, by: revokingDeviceID, at: now()) != nil else { return false }
        sessions.endSessions(for: deviceID)
        let whose = deviceID == revokingDeviceID ? "itself" : "another device"
        Self.logger.notice("A device revoked \(whose, privacy: .public)")
        return true
    }
}
