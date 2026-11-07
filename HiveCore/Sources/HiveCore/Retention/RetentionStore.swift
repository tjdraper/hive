import Foundation
import GRDB
import HiveKit

/// What a retention pass reads from the store, and whether each server fits its quota.
struct RetentionStore: Sendable {
    struct Job {
        let id: UUID
        let tiers: RetentionTiers
        /// Nil until the job is first backed up.
        let folders: SnapshotFolders?
    }

    struct Server {
        let id: UUID
        let quotaBytes: Int64?
        let jobs: [Job]
    }

    let database: HiveDatabase

    /// Every server, or only those in `ids`, with their jobs.
    func servers(_ ids: Set<UUID>? = nil) throws -> [Server] {
        try database.writer.read { database in
            let servers = try Row.fetchAll(database, sql: "SELECT id, quotaBytes, snapshotFolder FROM server")
            let jobs = try Row.fetchAll(database, sql: """
            SELECT id, serverID, dailySnapshots, monthlySnapshots, snapshotFolder FROM backupJob
            """)
            return servers.compactMap { server -> Server? in
                let id: UUID = server["id"]
                if let ids, !ids.contains(id) { return nil }
                let serverFolder: String? = server["snapshotFolder"]
                let ownJobs = jobs.filter { ($0["serverID"] as UUID) == id }.map { job in
                    Job(
                        id: job["id"],
                        tiers: RetentionTiers(dailySnapshots: job["dailySnapshots"], monthlySnapshots: job["monthlySnapshots"]),
                        folders: folders(server: serverFolder, job: job["snapshotFolder"])
                    )
                }
                return Server(id: id, quotaBytes: server["quotaBytes"], jobs: ownJobs)
            }
        }
    }

    func serverID(ofJob jobID: UUID) throws -> UUID? {
        try database.writer.read { try UUID.fetchOne($0, sql: "SELECT serverID FROM backupJob WHERE id = ?", arguments: [jobID]) }
    }

    /// The job's snapshots on the drive that aren't being removed.
    func snapshots(ofJob jobID: UUID, onDrive driveUUID: String) throws -> [SnapshotRecord] {
        try database.writer.read { database in
            try SnapshotRecord
                .filter(Column("jobID") == jobID && Column("driveUUID") == driveUUID)
                .filter(Column("state") != SnapshotState.removing.rawValue)
                .fetchAll(database)
        }
    }

    /// The folders a job and its server were given, for a job that may since have been removed.
    func folders(ofJob jobID: UUID) throws -> SnapshotFolders? {
        try database.writer.read { database in
            guard let row = try Row.fetchOne(database, sql: """
            SELECT server.snapshotFolder AS server, backupJob.snapshotFolder AS job
            FROM backupJob JOIN server ON server.id = backupJob.serverID
            WHERE backupJob.id = ?
            """, arguments: [jobID]) else { return nil }
            return folders(server: row["server"], job: row["job"])
        }
    }

    /// Set by a restore, until a device starts retention again (F3).
    func isPaused() throws -> Bool {
        try database.writer.read { try Date.fetchOne($0, sql: "SELECT retentionPausedSince FROM hive") != nil }
    }

    /// Keeps the date it first went over.
    func markOverQuota(serverID: UUID, at date: Date) throws {
        try database.writer.write { database in
            try database.execute(
                sql: "INSERT INTO overQuotaServer (serverID, since) VALUES (?, ?) ON CONFLICT (serverID) DO NOTHING",
                arguments: [serverID, date]
            )
        }
    }

    func clearOverQuota(serverID: UUID) throws {
        try database.writer.write { try $0.execute(sql: "DELETE FROM overQuotaServer WHERE serverID = ?", arguments: [serverID]) }
    }

    /// Servers still over their quota with only monthly and newest snapshots left, and since when.
    func overQuota() throws -> [UUID: Date] {
        try database.writer.read { database in
            let rows = try Row.fetchAll(database, sql: "SELECT serverID, since FROM overQuotaServer")
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["serverID"], $0["since"]) })
        }
    }

    private func folders(server: String?, job: String?) -> SnapshotFolders? {
        guard let server, let job else { return nil }
        return SnapshotFolders(server: server, job: job)
    }
}
