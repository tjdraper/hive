import Foundation
import GRDB
import HiveKit

/// When each job runs next, kept in the store so a time that passes while Hive is off is still noticed.
struct JobScheduleRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "jobSchedule"

    let jobID: UUID
    /// From `ScheduleCalendar.key(for:)`.
    var scheduleKey: String
    var nextRunAt: Date
}

struct ScheduleStore: Sendable {
    let database: HiveDatabase

    func all() throws -> [UUID: JobScheduleRecord] {
        let records = try database.writer.read { try JobScheduleRecord.fetchAll($0) }
        return Dictionary(uniqueKeysWithValues: records.map { ($0.jobID, $0) })
    }

    /// Works out the next run of a job whose times are new or changed from when they're saved, in the
    /// same transaction. Left to the scheduler's next check, a time coming in between would be missed.
    static func reschedule(jobID: UUID, times: [TimeOfDay], from date: Date, schedule: ScheduleCalendar, in database: Database) throws {
        let key = schedule.key(for: times)
        if let stored = try JobScheduleRecord.fetchOne(database, key: jobID), stored.scheduleKey == key { return }
        guard let next = schedule.nextRun(after: date, times: times) else { return }
        try JobScheduleRecord(jobID: jobID, scheduleKey: key, nextRunAt: next).save(database)
    }

    /// Ignored for a job removed meanwhile.
    func save(_ record: JobScheduleRecord) throws {
        try database.writer.write { database in
            guard try BackupJobRecord.exists(database, key: record.jobID) else { return }
            try record.save(database)
        }
    }
}
