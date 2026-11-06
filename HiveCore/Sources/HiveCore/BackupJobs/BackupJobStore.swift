import Foundation
import GRDB
import HiveKit

/// Backup jobs in Hive's store. Each change is saved with its audit entries, all or none of them.
struct BackupJobStore: Sendable {
    let database: HiveDatabase

    /// Every server's jobs.
    func all() throws -> [BackupJob] {
        try database.writer.read { database in
            try StoredBackupJob.fetchAll(serverID: nil, in: database).map { try $0.backupJob() }
        }
    }

    /// Nil when no server has that ID.
    func jobs(onServer serverID: UUID) throws -> [BackupJob]? {
        try database.writer.read { database in
            guard try ServerRecord.exists(database, key: serverID) else { return nil }
            return try StoredBackupJob.fetchAll(serverID: serverID, in: database).map { try $0.backupJob() }
        }
    }

    func job(id: UUID) throws -> BackupJob? {
        try database.writer.read { try StoredBackupJob.fetch(id: id, in: $0)?.backupJob() }
    }

    /// `sealed` has passed `BackupJobDraftCheck`. Returns nil when no server has that ID.
    func add(_ sealed: SealedJobDraft, toServer serverID: UUID, by deviceID: UUID, at date: Date) throws -> BackupJob? {
        try database.writer.write { database in
            guard let server = try ServerRecord.fetchOne(database, key: serverID) else { return nil }
            try Self.checkDatabaseIDs(in: sealed.draft, known: [])
            try Self.checkNameIsFree(sealed.draft.name, onServer: serverID, except: nil, in: database)

            let stored = StoredBackupJob(id: UUID(), serverID: serverID, createdAt: date, draft: sealed, existing: [])
            try stored.insert(in: database)
            let event = AuditEvent.backupJob(jobID: stored.job.id, serverName: server.name, jobName: stored.job.name, change: .added)
            try AuditLog.record(event, by: deviceID, at: date, in: database)
            return try stored.backupJob()
        }
    }

    /// Returns nil when no job has that ID.
    func change(id: UUID, to sealed: SealedJobDraft, by deviceID: UUID, at date: Date) throws -> (old: BackupJob, new: BackupJob)? {
        try database.writer.write { database in
            guard let stored = try StoredBackupJob.fetch(id: id, in: database) else { return nil }
            // Only a database's own ID carries its password, so a password can never move to another job or server.
            try Self.checkDatabaseIDs(in: sealed.draft, known: Set(stored.databases.map(\.id)))
            try Self.checkNameIsFree(sealed.draft.name, onServer: stored.job.serverID, except: id, in: database)

            let old = try stored.backupJob()
            let replacement = StoredBackupJob(
                id: id,
                serverID: stored.job.serverID,
                createdAt: stored.job.createdAt,
                draft: sealed,
                existing: stored.databases
            )
            try replacement.replace(in: database)
            let new = try replacement.backupJob()

            let serverName = try Self.serverName(stored.job.serverID, in: database)
            for change in Self.changes(from: old, to: new, passwordsEnteredAt: sealed.passwordPositions) {
                let event = AuditEvent.backupJob(jobID: id, serverName: serverName, jobName: new.name, change: change)
                try AuditLog.record(event, by: deviceID, at: date, in: database)
            }
            return (old, new)
        }
    }

    /// Its configuration only. Its snapshots stay on the backup drive. Returns nil when no job has that ID.
    func remove(id: UUID, by deviceID: UUID, at date: Date) throws -> BackupJob? {
        try database.writer.write { database in
            guard let stored = try StoredBackupJob.fetch(id: id, in: database) else { return nil }
            let serverName = try Self.serverName(stored.job.serverID, in: database)
            let event = AuditEvent.backupJob(jobID: id, serverName: serverName, jobName: stored.job.name, change: .removed)
            try AuditLog.record(event, by: deviceID, at: date, in: database)
            try stored.job.delete(database)
            return try stored.backupJob()
        }
    }

    /// `passwordsEnteredAt` are positions in `new.databases`.
    static func changes(from old: BackupJob, to new: BackupJob, passwordsEnteredAt: [Int]) -> [BackupJobChange] {
        var changes: [BackupJobChange] = []
        if old.name != new.name { changes.append(.renamed(old: old.name, new: new.name)) }
        if old.directories != new.directories { changes.append(.directories(old: old.directories, new: new.directories)) }
        let oldDatabases = old.databases.map(\.settings)
        let newDatabases = new.databases.map(\.settings)
        if oldDatabases != newDatabases { changes.append(.databases(old: oldDatabases, new: newDatabases)) }
        changes += passwordsEnteredAt.map { .databasePassword(databaseName: new.databases[$0].settings.name) }
        if old.times != new.times { changes.append(.times(old: old.times, new: new.times)) }
        if old.retention != new.retention { changes.append(.retention(old: old.retention, new: new.retention)) }
        return changes
    }

    private static func checkDatabaseIDs(in draft: BackupJobDraft, known: Set<UUID>) throws {
        let problems = draft.databases.enumerated().compactMap { index, database in
            database.id.flatMap { known.contains($0) ? nil : ConfigurationProblem(field: .database, index: index, reason: .unknown) }
        }
        if !problems.isEmpty { throw ConfigurationChangeError.refused(problems) }
    }

    /// Two jobs with the same name on one server couldn't be told apart in Beekeeper.
    private static func checkNameIsFree(_ name: String, onServer serverID: UUID, except id: UUID?, in database: Database) throws {
        let taken = try BackupJobRecord.filter(Column("serverID") == serverID).fetchAll(database).contains {
            $0.id != id && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        if taken { throw ConfigurationChangeError.refused([ConfigurationProblem(field: .name, reason: .duplicate)]) }
    }

    private static func serverName(_ serverID: UUID, in database: Database) throws -> String {
        try String.fetchOne(database, sql: "SELECT name FROM server WHERE id = ?", arguments: [serverID]) ?? ""
    }
}
