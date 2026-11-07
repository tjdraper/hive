import Foundation
import GRDB

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

    /// Ignored for a job removed meanwhile.
    func save(_ record: JobScheduleRecord) throws {
        try database.writer.write { database in
            guard try BackupJobRecord.exists(database, key: record.jobID) else { return }
            try record.save(database)
        }
    }
}
