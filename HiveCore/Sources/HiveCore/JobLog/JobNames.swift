import Foundation
import GRDB

/// A job's and its server's names as they are now, copied into the job log and the audit log so their
/// entries outlive both.
struct JobNames {
    let serverID: UUID
    let server: String
    let job: String

    /// Nil when there's no such job.
    static func fetch(jobID: UUID, in database: Database) throws -> JobNames? {
        guard let row = try Row.fetchOne(
            database,
            sql: """
            SELECT server.id AS serverID, server.name AS serverName, backupJob.name AS jobName
            FROM backupJob JOIN server ON server.id = backupJob.serverID
            WHERE backupJob.id = ?
            """,
            arguments: [jobID]
        ) else { return nil }
        return JobNames(serverID: row["serverID"], server: row["serverName"], job: row["jobName"])
    }

    /// The names now, or for a removed job as last known: its newest job log entry, and failing that,
    /// since entries go after a year, the folders its snapshots are in. Nil when Hive has no trace of it.
    static func lastKnown(jobID: UUID, in database: Database) throws -> JobNames? {
        if let names = try fetch(jobID: jobID, in: database) { return names }
        if let row = try Row.fetchOne(
            database,
            sql: "SELECT serverID, serverName, jobName FROM jobLogEntry WHERE jobID = ? ORDER BY id DESC LIMIT 1",
            arguments: [jobID]
        ) {
            let serverID: UUID = row["serverID"]
            return JobNames(serverID: serverID, server: try serverName(serverID, in: database) ?? row["serverName"], job: row["jobName"])
        }
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT serverID, serverFolder, jobFolder FROM snapshot WHERE jobID = ? LIMIT 1",
            arguments: [jobID]
        ) else { return nil }
        let serverID: UUID = row["serverID"]
        return JobNames(serverID: serverID, server: try serverName(serverID, in: database) ?? row["serverFolder"], job: row["jobFolder"])
    }

    /// The server's name now, or for a removed server as last known, as `lastKnown(jobID:in:)` finds it.
    static func lastKnownServerName(_ serverID: UUID, in database: Database) throws -> String? {
        if let name = try serverName(serverID, in: database) { return name }
        if let name = try String.fetchOne(
            database,
            sql: "SELECT serverName FROM jobLogEntry WHERE serverID = ? ORDER BY id DESC LIMIT 1",
            arguments: [serverID]
        ) { return name }
        return try String.fetchOne(database, sql: "SELECT serverFolder FROM snapshot WHERE serverID = ? LIMIT 1", arguments: [serverID])
    }

    private static func serverName(_ serverID: UUID, in database: Database) throws -> String? {
        try String.fetchOne(database, sql: "SELECT name FROM server WHERE id = ?", arguments: [serverID])
    }
}
