import Foundation
import GRDB
import HiveKit

/// Whether the Hive can be restored, and after a restore, what it took over while retention waits.
struct RestoreStateReader: Sendable {
    let database: HiveDatabase

    func state() throws -> RestoreState {
        try database.writer.read { database in
            let pausedSince = try Date.fetchOne(database, sql: "SELECT retentionPausedSince FROM hive")
            return RestoreState(
                canRestore: try RecoveryContentsWriter.isUnconfigured(in: database),
                retentionPausedSince: pausedSince,
                servers: pausedSince == nil ? [] : try Self.servers(in: database)
            )
        }
    }

    private static func servers(in database: Database) throws -> [RestoredServer] {
        let driveUUID = try BackupDriveStore.chosen(in: database)?.volumeUUID.uuidString
        let jobs = try Row.fetchAll(database, sql: """
        SELECT
            backupJob.id, backupJob.serverID, backupJob.name,
            (SELECT COUNT(*) FROM snapshot
                WHERE snapshot.jobID = backupJob.id AND snapshot.driveUUID = :drive AND snapshot.state = :complete) AS snapshots,
            EXISTS (SELECT 1 FROM snapshot WHERE snapshot.jobID = backupJob.id AND snapshot.driveUUID = :drive) AS hasSnapshots,
            (SELECT usedBytes FROM jobSpace WHERE jobSpace.jobID = backupJob.id AND jobSpace.driveUUID = :drive) AS usedBytes
        FROM backupJob ORDER BY backupJob.createdAt, backupJob.id
        """, arguments: ["drive": driveUUID, "complete": SnapshotState.complete.rawValue])
        let byServer = Dictionary(grouping: jobs) { $0["serverID"] as UUID }

        return try Row.fetchAll(database, sql: "SELECT id, name, quotaBytes FROM server ORDER BY createdAt, id").map { row in
            let id: UUID = row["id"]
            let ownJobs = byServer[id, default: []]
            // Measured as its quota is: the sum of its jobs', unknown while any job with snapshots is uncounted.
            var used: Int64? = 0
            for job in ownJobs where job["hasSnapshots"] as Bool {
                guard let jobUsed = job["usedBytes"] as Int64? else {
                    used = nil
                    break
                }
                used? += jobUsed
            }
            return RestoredServer(
                id: id,
                name: row["name"],
                quotaBytes: row["quotaBytes"],
                usedBytes: used,
                jobs: ownJobs.map { RestoredJob(id: $0["id"], name: $0["name"], snapshotCount: $0["snapshots"]) }
            )
        }
    }
}
