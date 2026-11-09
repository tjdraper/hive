import Foundation
import GRDB
import HiveKit

/// A server's space on the chosen backup drive, measured the way its quota is: the sum of its jobs'.
/// Snapshots of jobs it no longer has, and those on another drive, aren't counted against it.
struct ServerSpaceReader: Sendable {
    let database: HiveDatabase

    /// Nil when no server has that ID.
    func space(ofServer serverID: UUID) throws -> ServerSpace? {
        try database.writer.read { database in
            guard try Bool.fetchOne(database, sql: "SELECT 1 FROM server WHERE id = ?", arguments: [serverID]) != nil else {
                return nil
            }
            guard let drive = try BackupDriveStore.chosen(in: database) else { return ServerSpace(usedBytes: 0) }
            let jobs = try Row.fetchAll(database, sql: """
            SELECT
                EXISTS (SELECT 1 FROM snapshot WHERE snapshot.jobID = backupJob.id AND snapshot.driveUUID = :drive) AS hasSnapshots,
                (SELECT usedBytes FROM jobSpace WHERE jobSpace.jobID = backupJob.id AND jobSpace.driveUUID = :drive) AS usedBytes
            FROM backupJob WHERE serverID = :server
            """, arguments: ["drive": drive.volumeUUID.uuidString, "server": serverID])

            var total: Int64 = 0
            for job in jobs where job["hasSnapshots"] as Bool {
                guard let used = job["usedBytes"] as Int64? else { return ServerSpace(usedBytes: nil) }
                total += used
            }
            return ServerSpace(usedBytes: total)
        }
    }
}
