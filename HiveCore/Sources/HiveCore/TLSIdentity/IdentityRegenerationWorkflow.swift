import Foundation
import GRDB
import HiveKit
import os

/// Gives Hive a new identity key (§5). Every device pinned the old one, so each is unpaired and has to
/// pair again: Beekeeper on the Hive Mac by itself, any other through a device that has. Hive restarts
/// to take up the new key, issuing a certificate for it as it starts.
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

        let unpaired = try database.writer.write { database in
            // Recorded first, since the device that asked is about to go with the rest.
            try AuditLog.record(.identityRegenerated, by: deviceID, at: now(), in: database)
            return try PairedDevice.deleteAll(database)
        }
        sessions.endAllSessions()
        Self.logger.notice("Unpaired \(unpaired, privacy: .public) devices for a new identity")

        // Every device is unpaired whether or not this works, and Hive restarts either way, so it can't
        // carry on serving devices it no longer knows.
        defer { restart.request() }
        try keys.replaceIdentityKey(with: key)
    }
}
