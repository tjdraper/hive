import Foundation
import GRDB
import HiveKit

/// Jobs no longer in the configuration whose snapshots stayed on the chosen backup drive (§10), so a
/// device can find and delete them.
struct RemovedJobReader: Sendable {
    let database: HiveDatabase

    /// Newest snapshot first.
    func removedJobs() throws -> [RemovedJob] {
        try database.writer.read { database in
            guard let drive = try BackupDriveStore.chosen(in: database) else { return [] }
            let driveUUID = drive.volumeUUID.uuidString
            let rows = try Row.fetchAll(database, sql: """
            SELECT jobID, serverID, COUNT(*) AS count, MAX(COALESCE(completedAt, startedAt)) AS newest
            FROM snapshot
            WHERE driveUUID = ? AND jobID NOT IN (SELECT id FROM backupJob)
            GROUP BY jobID
            ORDER BY newest DESC
            """, arguments: [driveUUID])
            return try rows.map { row in
                let jobID: UUID = row["jobID"]
                let serverID: UUID = row["serverID"]
                let names = try JobNames.lastKnown(jobID: jobID, in: database)
                return RemovedJob(
                    jobID: jobID,
                    serverID: serverID,
                    serverName: names?.server ?? "",
                    jobName: names?.job ?? "",
                    isServerRemoved: try !ServerRecord.exists(database, key: serverID),
                    snapshotCount: row["count"],
                    usedBytes: try SnapshotSpaceStore.usedBytes(ofJob: jobID, onDrive: driveUUID, in: database),
                    newestSnapshotAt: row["newest"]
                )
            }
        }
    }
}
