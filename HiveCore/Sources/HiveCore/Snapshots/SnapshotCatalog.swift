import Foundation
import GRDB
import HiveKit

enum SnapshotState: String, Codable {
    /// Being written, or left by a run that failed, for the next run to pick up.
    case partial
    case complete
    /// Retention is removing it. Its folder may already be renamed `<folder>.removing`, and partly gone.
    case removing
}

/// One snapshot on a backup drive. It outlives its job and server, whose snapshots stay when their
/// configuration is removed.
struct SnapshotRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "snapshot"

    let id: UUID
    let jobID: UUID
    let serverID: UUID
    let driveUUID: String
    let serverFolder: String
    let jobFolder: String
    /// `<date-time>.partial` until it's complete, then `<date-time>`.
    var folder: String
    var state: SnapshotState
    let startedAt: Date
    var completedAt: Date?
    /// Whether its files are in its job's space on the drive. Every snapshot is, but one being written.
    var isCounted = false
    /// What removing it would free, as last counted. Nil until it's counted, and after a change nearby
    /// may have moved it.
    var freesBytes: Int64?
    /// Why it's being removed.
    var removalReason: RemovalReason?

    /// When it completed, or for one that hasn't, when it started.
    var date: Date {
        completedAt ?? startedAt
    }

    /// Its folder under the drive's `Hive` folder.
    var parts: [String] {
        [serverFolder, jobFolder, folder]
    }
}

/// The snapshots Hive has made, kept in its store as each one is made.
struct SnapshotCatalog: Sendable {
    let database: HiveDatabase

    func add(_ record: SnapshotRecord) throws {
        try database.writer.write { try record.insert($0) }
    }

    /// Newest first: complete ones by when they completed, since a partial picked up days later
    /// completes after snapshots that started after it.
    func snapshots(ofJob jobID: UUID, onDrive driveUUID: UUID, in state: SnapshotState) throws -> [SnapshotRecord] {
        try database.writer.read { database in
            try SnapshotRecord
                .filter(Column("jobID") == jobID && Column("driveUUID") == driveUUID.uuidString && Column("state") == state.rawValue)
                .order(Column("completedAt").desc, Column("startedAt").desc)
                .fetchAll(database)
        }
    }

    /// A run is carrying on with a partial snapshot, so its files leave its job's space until the run
    /// ends and it's counted again. Otherwise what the run adds couldn't be told from what was there.
    func pickUp(_ id: UUID) throws {
        try database.writer.write { database in
            guard var record = try SnapshotRecord.fetchOne(database, key: id), record.isCounted else { return }
            try SnapshotSpaceStore.uncount(record, in: database)
            record.isCounted = false
            record.freesBytes = nil
            try record.update(database)
        }
    }

    func markComplete(_ id: UUID, folder: String, at date: Date) throws {
        try database.writer.write { database in
            guard var record = try SnapshotRecord.fetchOne(database, key: id) else { return }
            record.folder = folder
            record.state = .complete
            record.completedAt = date
            try record.update(database)
        }
    }

    /// Only for a snapshot whose folder isn't on the drive, so there's nothing there to keep track of.
    func forget(_ id: UUID) throws {
        _ = try database.writer.write { try SnapshotRecord.deleteOne($0, key: id) }
    }
}
