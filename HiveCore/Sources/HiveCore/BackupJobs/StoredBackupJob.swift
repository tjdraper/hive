import Foundation
import GRDB
import HiveKit

/// A job's rows across its tables.
struct StoredBackupJob {
    var job: BackupJobRecord
    var directories: [BackupDirectoryRecord]
    var databases: [BackupDatabaseRecord]
    var times: [BackupTimeRecord]

    /// Passwords come from `draft` where one was entered, and otherwise from the database with the same
    /// ID in `existing`.
    init(id: UUID, serverID: UUID, createdAt: Date, draft sealed: SealedJobDraft, existing: [BackupDatabaseRecord]) {
        let draft = sealed.draft
        job = BackupJobRecord(
            id: id,
            serverID: serverID,
            name: draft.name,
            dailySnapshots: draft.retention.dailySnapshots,
            monthlySnapshots: draft.retention.monthlySnapshots,
            createdAt: createdAt
        )
        directories = draft.directories.enumerated().map { position, directory in
            BackupDirectoryRecord(jobID: id, position: position, path: directory.path, folder: directory.folder)
        }
        let existingPasswords = Dictionary(uniqueKeysWithValues: existing.compactMap { database in
            database.sealedPassword.map { (database.id, $0) }
        })
        databases = zip(draft.databases, sealed.newPasswords).enumerated().map { position, entry in
            let (database, newPassword) = entry
            let databaseID = database.id ?? UUID()
            return BackupDatabaseRecord(
                id: databaseID,
                jobID: id,
                position: position,
                settings: database.settings,
                sealedPassword: newPassword?.data ?? existingPasswords[databaseID]
            )
        }
        times = draft.times.map { BackupTimeRecord(jobID: id, minuteOfDay: $0.hour * 60 + $0.minute) }
    }

    private init(job: BackupJobRecord, directories: [BackupDirectoryRecord], databases: [BackupDatabaseRecord], times: [BackupTimeRecord]) {
        self.job = job
        self.directories = directories
        self.databases = databases
        self.times = times
    }

    static func fetch(id: UUID, in database: Database) throws -> StoredBackupJob? {
        guard let job = try BackupJobRecord.fetchOne(database, key: id) else { return nil }
        return try fetchAll([job], in: database).first
    }

    /// Every job, or every job on one server, in name order.
    static func fetchAll(serverID: UUID?, in database: Database) throws -> [StoredBackupJob] {
        var request = BackupJobRecord.all()
        if let serverID { request = request.filter(Column("serverID") == serverID) }
        return try fetchAll(request.fetchAll(database), in: database)
            .sorted { $0.job.name.localizedStandardCompare($1.job.name) == .orderedAscending }
    }

    private static func fetchAll(_ jobs: [BackupJobRecord], in database: Database) throws -> [StoredBackupJob] {
        let ids = jobs.map(\.id)
        let directories = try Dictionary(
            grouping: BackupDirectoryRecord.filter(ids.contains(Column("jobID"))).order(Column("position")).fetchAll(database),
            by: \.jobID
        )
        let databases = try Dictionary(
            grouping: BackupDatabaseRecord.filter(ids.contains(Column("jobID"))).order(Column("position")).fetchAll(database),
            by: \.jobID
        )
        let times = try Dictionary(
            grouping: BackupTimeRecord.filter(ids.contains(Column("jobID"))).order(Column("minuteOfDay")).fetchAll(database),
            by: \.jobID
        )
        return jobs.map { job in
            StoredBackupJob(
                job: job,
                directories: directories[job.id] ?? [],
                databases: databases[job.id] ?? [],
                times: times[job.id] ?? []
            )
        }
    }

    func insert(in database: Database) throws {
        try job.insert(database)
        try insertParts(in: database)
    }

    /// Replaces the job's row and everything under it.
    func replace(in database: Database) throws {
        try job.update(database)
        try BackupDirectoryRecord.filter(Column("jobID") == job.id).deleteAll(database)
        try BackupDatabaseRecord.filter(Column("jobID") == job.id).deleteAll(database)
        try BackupTimeRecord.filter(Column("jobID") == job.id).deleteAll(database)
        try insertParts(in: database)
    }

    private func insertParts(in database: Database) throws {
        for directory in directories { try directory.insert(database) }
        for backupDatabase in databases { try backupDatabase.insert(database) }
        for time in times { try time.insert(database) }
    }

    func backupJob() throws -> BackupJob {
        BackupJob(
            id: job.id,
            serverID: job.serverID,
            name: job.name,
            directories: directories.map { BackupDirectory(path: $0.path, folder: $0.folder) },
            databases: try databases.map { BackupDatabase(id: $0.id, settings: try $0.settings(), hasPassword: $0.sealedPassword != nil) },
            times: times.map { TimeOfDay(hour: $0.minuteOfDay / 60, minute: $0.minuteOfDay % 60) },
            retention: RetentionTiers(dailySnapshots: job.dailySnapshots, monthlySnapshots: job.monthlySnapshots)
        )
    }
}

struct BackupJobRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "backupJob"

    let id: UUID
    let serverID: UUID
    var name: String
    var dailySnapshots: Int
    var monthlySnapshots: Int
    let createdAt: Date
}

struct BackupDirectoryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "backupDirectory"

    let jobID: UUID
    let position: Int
    let path: String
    let folder: String
}

struct BackupDatabaseRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "backupDatabase"

    let id: UUID
    let jobID: UUID
    let position: Int
    let kind: String
    let serviceName: String?
    let user: String
    let name: String
    /// A `SealedSecret`.
    let sealedPassword: Data?

    init(id: UUID, jobID: UUID, position: Int, settings: DatabaseSettings, sealedPassword: Data?) {
        self.id = id
        self.jobID = jobID
        self.position = position
        kind = settings.kind.rawValue
        serviceName = switch settings.location {
        case .host: nil
        case .container(let serviceName): serviceName
        }
        user = settings.user
        name = settings.name
        self.sealedPassword = sealedPassword
    }

    func settings() throws -> DatabaseSettings {
        guard let kind = DatabaseKind(rawValue: kind) else { throw BackupJobStoreError.unknownDatabaseKind }
        return DatabaseSettings(
            kind: kind,
            location: serviceName.map { .container(serviceName: $0) } ?? .host,
            user: user,
            name: name
        )
    }
}

struct BackupTimeRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "backupTime"

    let jobID: UUID
    let minuteOfDay: Int
}

enum BackupJobStoreError: Error, Equatable {
    case unknownDatabaseKind
}
