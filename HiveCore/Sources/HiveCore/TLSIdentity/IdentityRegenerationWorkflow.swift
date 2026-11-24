import Foundation
import GRDB
import HiveKit
import os

/// Gives Hive a new identity key (§5). Every device pinned the old one, so each is unpaired and has to
/// pair again: Beekeeper on the Hive Mac by itself, any other through a device that has. Hive restarts
/// to take up the new key, issuing a certificate for it as it starts. Every Scout pinned the old key
/// too, so each is removed, and its server waits for one to enroll again.
struct IdentityRegenerationWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "TLSIdentity")

    let keys: HiveKeyStore
    let database: HiveDatabase
    let sessions: SessionStore
    let restart: HiveRestart
    let now: @Sendable () -> Date

    /// Throws `ConfirmationError.required`, changing nothing, unless confirmed.
    func regenerate(isConfirmed: Bool, by deviceID: UUID) throws {
        try ConfirmationRequirement.check([.identityRegenerated], isConfirmed: isConfirmed)
        // Made first, so failing to make one changes nothing.
        let key = try keys.makeIdentityKey()

        let removed = try database.writer.write { database in
            // Recorded first, since the device that asked is about to go with the rest.
            try AuditLog.record(.identityRegenerated, by: deviceID, at: now(), in: database)
            return (devices: try PairedDevice.deleteAll(database), scouts: try ScoutRecord.deleteAll(database))
        }
        sessions.endAllSessions()
        Self.logger.notice("""
        Unpaired \(removed.devices, privacy: .public) devices and removed \(removed.scouts, privacy: .public) Scouts \
        for a new identity
        """)

        // Every device is unpaired whether or not this works, and Hive restarts either way, so it can't
        // carry on serving devices it no longer knows.
        defer { restart.request() }
        try keys.replaceIdentityKey(with: key)
    }
}
