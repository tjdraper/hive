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
}
