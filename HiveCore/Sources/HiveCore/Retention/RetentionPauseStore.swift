import Foundation
import GRDB
import HiveKit

/// Retention and quotas, paused by a restore until a device starts them again (§10).
struct RetentionPauseStore: Sendable {
    let database: HiveDatabase

    /// Throws `ConfirmationError.required`, changing nothing, unless confirmed. False when retention
    /// wasn't paused.
    func startRetention(isConfirmed: Bool, by deviceID: UUID, at date: Date) throws -> Bool {
        try database.writer.write { database in
            guard try Date.fetchOne(database, sql: "SELECT retentionPausedSince FROM hive") != nil else { return false }
            try ConfirmationRequirement.check([.retentionStarted], isConfirmed: isConfirmed)
            try database.execute(sql: "UPDATE hive SET retentionPausedSince = NULL")
            try AuditLog.record(.retentionStarted, by: deviceID, at: date, in: database)
            return true
        }
    }
}
