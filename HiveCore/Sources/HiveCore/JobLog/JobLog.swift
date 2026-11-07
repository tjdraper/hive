import Foundation
import GRDB
import HiveKit

/// Hive's record of each run (§12): which job, each directory and database, how long each took, what
/// it transferred and why anything failed. Entries are kept for a year.
struct JobLog: Sendable {
    static let largestPage = 500

    let database: HiveDatabase

    /// Newest first, starting after the entry `before` when given.
    func page(before: Int64?, limit: Int, jobID: UUID? = nil, serverID: UUID? = nil) throws -> JobLogPage {
        let limit = min(max(limit, 1), Self.largestPage)
        let records = try database.writer.read { database in
            var request = JobLogRecord.order(Column("id").desc).limit(limit + 1)
            if let before { request = request.filter(Column("id") < before) }
            if let jobID { request = request.filter(Column("jobID") == jobID) }
            if let serverID { request = request.filter(Column("serverID") == serverID) }
            return try request.fetchAll(database)
        }
        let entries = records.prefix(limit).compactMap(\.entry)
        return JobLogPage(entries: entries, nextBefore: records.count > limit ? entries.last?.id : nil)
    }

    /// The job's newest run that has finished.
    func lastFinished(ofJob jobID: UUID) throws -> JobLogEntry? {
        try database.writer.read { database in
            try JobLogRecord
                .filter(Column("jobID") == jobID && Column("finishedAt") != nil)
                .order(Column("id").desc)
                .fetchOne(database)?
                .entry
        }
    }

    /// Removes finished entries that started before `date`. Returns how many.
    func removeEntries(startedBefore date: Date) throws -> Int {
        try database.writer.write { database in
            try JobLogRecord.filter(Column("startedAt") < date && Column("finishedAt") != nil).deleteAll(database)
        }
    }
}

struct JobLogRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "jobLogEntry"

    var id: Int64?
    let jobID: UUID
    let serverID: UUID
    let serverName: String
    let jobName: String
    let trigger: RunTrigger
    let startedAt: Date
    var finishedAt: Date?
    var failure: BackupFailure?
    var pickedUpPartialSnapshot: Bool
    /// Kept as JSON, which GRDB does for a property that isn't a database value.
    var directories: [DirectoryRun]
    var databases: [DatabaseRun]

    var run: BackupRun {
        BackupRun(
            jobID: jobID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            failure: failure,
            directories: directories,
            databases: databases,
            pickedUpPartialSnapshot: pickedUpPartialSnapshot
        )
    }

    var entry: JobLogEntry? {
        id.map { JobLogEntry(id: $0, serverID: serverID, serverName: serverName, jobName: jobName, trigger: trigger, run: run) }
    }

    /// Takes on everything the run reported but when it started.
    mutating func record(_ run: BackupRun) {
        finishedAt = run.finishedAt
        failure = run.failure
        pickedUpPartialSnapshot = run.pickedUpPartialSnapshot
        directories = run.directories
        databases = run.databases
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
