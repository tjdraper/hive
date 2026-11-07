import Foundation
import GRDB
import HiveKit

/// Hive's record of each run (§12): which job, each directory and database, how long each took, what
/// it transferred and why anything failed. It also records what retention removed. Entries are kept
/// for a year.
struct JobLog: Sendable {
    static let largestPage = 500

    let database: HiveDatabase

    /// Newest first, starting after the entry `before` when given.
    func page(before: Int64?, limit: Int, jobID: UUID? = nil, serverID: UUID? = nil) throws -> JobLogPage {
        let limit = min(max(limit, 1), Self.largestPage)
        let rows = try database.writer.read { database in
            var request = JobLogRecord.order(Column("id").desc).limit(limit + 1)
            if let before { request = request.filter(Column("id") < before) }
            if let jobID { request = request.filter(Column("jobID") == jobID) }
            if let serverID { request = request.filter(Column("serverID") == serverID) }
            return try Row.fetchAll(database, request)
        }
        let entries = try rows.prefix(limit).compactMap { row -> JobLogEntry? in
            if row[JobLogRecord.kindColumn] == RemovalLogRecord.kind {
                return try RemovalLogRecord(row: row).entry.map(JobLogEntry.removal)
            }
            return try JobLogRecord(row: row).entry.map(JobLogEntry.run)
        }
        return JobLogPage(entries: entries, nextBefore: rows.count > limit ? entries.last?.id : nil)
    }

    /// One entry for the job, when anything was removed or couldn't be.
    func recordRemovals(
        ofJob jobID: UUID,
        removed: [RemovedSnapshot],
        notRemoved: [UnremovedSnapshot],
        at date: Date
    ) throws {
        guard !removed.isEmpty || !notRemoved.isEmpty else { return }
        try database.writer.write { database in
            guard let names = try JobNames.fetch(jobID: jobID, in: database) else { return }
            var record = RemovalLogRecord(
                id: nil,
                jobID: jobID,
                serverID: names.serverID,
                serverName: names.server,
                jobName: names.job,
                startedAt: date,
                finishedAt: date,
                removed: removed,
                notRemoved: notRemoved
            )
            try record.insert(database)
        }
    }

    /// The job's newest run that has finished.
    func lastFinished(ofJob jobID: UUID) throws -> RunLogEntry? {
        try database.writer.read { database in
            try JobLogRecord
                .filter(Column("jobID") == jobID && Column("finishedAt") != nil && JobLogRecord.kindColumn != RemovalLogRecord.kind)
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

/// A run in the job log. Its `kind` is left to the table, which makes it a run.
struct JobLogRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "jobLogEntry"
    static let kindColumn = Column("kind")

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

    var entry: RunLogEntry? {
        id.map { RunLogEntry(id: $0, serverID: serverID, serverName: serverName, jobName: jobName, trigger: trigger, run: run) }
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

/// What retention removed from one job in one pass, in the same table as runs, so the job log reads
/// as one list.
struct RemovalLogRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "jobLogEntry"
    static let kind = "removal"

    var id: Int64?
    var kind = Self.kind
    let jobID: UUID
    let serverID: UUID
    let serverName: String
    let jobName: String
    /// When the pass removed them. `finishedAt` is the same, so nothing reads it as a run still going.
    let startedAt: Date
    let finishedAt: Date
    let removed: [RemovedSnapshot]
    let notRemoved: [UnremovedSnapshot]

    init(
        id: Int64?,
        jobID: UUID,
        serverID: UUID,
        serverName: String,
        jobName: String,
        startedAt: Date,
        finishedAt: Date,
        removed: [RemovedSnapshot],
        notRemoved: [UnremovedSnapshot]
    ) {
        self.id = id
        self.jobID = jobID
        self.serverID = serverID
        self.serverName = serverName
        self.jobName = jobName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.removed = removed
        self.notRemoved = notRemoved
    }

    var entry: RemovalLogEntry? {
        id.map {
            RemovalLogEntry(
                id: $0,
                jobID: jobID,
                serverID: serverID,
                serverName: serverName,
                jobName: jobName,
                date: startedAt,
                removed: removed,
                notRemoved: notRemoved
            )
        }
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
