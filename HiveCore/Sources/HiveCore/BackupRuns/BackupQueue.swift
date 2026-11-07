import Foundation
import GRDB
import HiveKit

/// A run waiting its turn, or running. Kept in the store, so the queue survives a restart.
struct QueuedRunRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "queuedRun"

    let jobID: UUID
    var trigger: RunTrigger
    let queuedAt: Date
    /// Set while it runs.
    var logEntryID: Int64?
}

/// The job queue in Hive's store. Each job waits in it at most once, and its entry stays while it runs.
struct BackupQueue: Sendable {
    enum Addition: Equatable {
        case queued
        /// The job is already waiting or running.
        case alreadyQueued
        case unknownJob
    }

    enum Cancellation: Equatable {
        /// It hadn't started, and has left the queue.
        case leftQueue
        /// It's running, and has to be stopped.
        case running
        /// The job isn't waiting or running, or doesn't exist.
        case notQueued
    }

    let database: HiveDatabase

    /// Run Now is recorded in the audit log, as `deviceID`, in the same transaction.
    func add(jobID: UUID, trigger: RunTrigger, at date: Date, by deviceID: UUID? = nil) throws -> Addition {
        try database.writer.write { database in
            guard let names = try Self.names(ofJob: jobID, in: database) else { return .unknownJob }
            guard try !QueuedRunRecord.exists(database, key: jobID) else { return .alreadyQueued }
            try QueuedRunRecord(jobID: jobID, trigger: trigger, queuedAt: date, logEntryID: nil).insert(database)
            if let deviceID {
                let event = AuditEvent.backupRunStarted(jobID: jobID, serverName: names.server, jobName: names.job)
                try AuditLog.record(event, by: deviceID, at: date, in: database)
            }
            return .queued
        }
    }

    /// Recorded in the audit log in the same transaction. A running run leaves the queue once it stops.
    func cancel(jobID: UUID, by deviceID: UUID, at date: Date) throws -> Cancellation {
        try database.writer.write { database in
            guard let queued = try QueuedRunRecord.fetchOne(database, key: jobID),
                  let names = try Self.names(ofJob: jobID, in: database)
            else { return .notQueued }
            let event = AuditEvent.backupRunCancelled(jobID: jobID, serverName: names.server, jobName: names.job)
            try AuditLog.record(event, by: deviceID, at: date, in: database)
            guard queued.logEntryID == nil else { return .running }
            try queued.delete(database)
            return .leftQueue
        }
    }

    /// The run to go next: Run Now ahead of the rest, then in the order they were queued.
    func next() throws -> QueuedRunRecord? {
        try database.writer.read { database in
            try QueuedRunRecord
                .filter(Column("logEntryID") == nil)
                .order(sql: #""trigger" = ? DESC, queuedAt, rowid"#, arguments: [RunTrigger.runNow.rawValue])
                .fetchOne(database)
        }
    }

    /// Starts the job's entry in the job log, and marks it running, together. Nil when the job has
    /// been removed since it was queued.
    func begin(_ queued: QueuedRunRecord, at date: Date) throws -> JobLogRecord? {
        try database.writer.write { database in
            guard var running = try QueuedRunRecord.fetchOne(database, key: queued.jobID) else { return nil }
            guard let names = try Self.names(ofJob: queued.jobID, in: database) else {
                try running.delete(database)
                return nil
            }
            var entry = JobLogRecord(
                id: nil,
                jobID: queued.jobID,
                serverID: names.serverID,
                serverName: names.server,
                jobName: names.job,
                trigger: running.trigger,
                startedAt: date,
                finishedAt: nil,
                failure: nil,
                pickedUpPartialSnapshot: false,
                directories: [],
                databases: []
            )
            try entry.insert(database)
            running.logEntryID = entry.id
            try running.update(database)
            return entry
        }
    }

    /// Saves what the run has done so far.
    func save(_ entry: JobLogRecord) throws {
        try database.writer.write { try entry.update($0) }
    }

    /// Saves the finished run, and takes the job out of the queue, together.
    func finish(_ entry: JobLogRecord) throws {
        try database.writer.write { database in
            try entry.update(database)
            try QueuedRunRecord.filter(Column("logEntryID") == entry.id).deleteAll(database)
        }
    }

    /// After a restart: every run that was going is marked interrupted, and its job queued once more
    /// unless that run was already the one queued after an interruption. Returns how many were marked.
    func recoverInterruptedRuns(at date: Date) throws -> Int {
        try database.writer.write { database in
            let unfinished = try JobLogRecord.filter(Column("finishedAt") == nil).fetchAll(database)
            for var entry in unfinished {
                entry.finishedAt = date
                entry.failure = .interrupted
                try entry.update(database)
            }
            for var running in try QueuedRunRecord.filter(Column("logEntryID") != nil).fetchAll(database) {
                if running.trigger == .afterInterruption {
                    try running.delete(database)
                } else {
                    running.trigger = .afterInterruption
                    running.logEntryID = nil
                    try running.update(database)
                }
            }
            return unfinished.count
        }
    }

    /// Each queued job, and whether it's running.
    func all() throws -> [QueuedRunRecord] {
        try database.writer.read { try QueuedRunRecord.fetchAll($0) }
    }

    private struct JobNames {
        let serverID: UUID
        let server: String
        let job: String
    }

    private static func names(ofJob jobID: UUID, in database: Database) throws -> JobNames? {
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
