import Foundation
import GRDB
import HiveKit

/// The space each job's snapshots take on a backup drive, and what removing each would free, kept in
/// the catalog so they're recounted only where a run or a removal changed something (§10). A job's
/// space counts each file once, however many of its snapshots link to it, and covers every snapshot
/// marked counted.
struct SnapshotSpaceStore: Sendable {
    let database: HiveDatabase

    /// Nil until the job's snapshots on the drive have been counted.
    func usedBytes(ofJob jobID: UUID, onDrive driveUUID: String) throws -> Int64? {
        try database.writer.read { try Self.usedBytes(ofJob: jobID, onDrive: driveUUID, in: $0) }
    }

    /// Adds one snapshot's files that no other snapshot links to, when every other snapshot of its job
    /// is counted already.
    func recordCount(of id: UUID, freesBytes: Int64) throws {
        try database.writer.write { database in
            guard var record = try SnapshotRecord.fetchOne(database, key: id), !record.isCounted else { return }
            if let used = try Self.usedBytes(ofJob: record.jobID, onDrive: record.driveUUID, in: database) {
                try Self.setUsedBytes(used + freesBytes, ofJob: record.jobID, onDrive: record.driveUUID, in: database)
            }
            record.isCounted = true
            record.freesBytes = freesBytes
            try record.update(database)
            // A new snapshot links to its job's newest complete one, which then frees less.
            try SnapshotRecord
                .filter(Column("jobID") == record.jobID && Column("driveUUID") == record.driveUUID)
                .filter(Column("state") == SnapshotState.complete.rawValue && Column("id") != id)
                .order(Column("completedAt").desc)
                .limit(1)
                .updateAll(database, Column("freesBytes").set(to: nil))
        }
    }

    /// A fresh count of a counted snapshot, which doesn't change its job's space.
    func recordFreesBytes(_ bytes: Int64, of id: UUID) throws {
        _ = try database.writer.write { database in
            try SnapshotRecord
                .filter(key: id)
                .filter(Column("isCounted") == true)
                .updateAll(database, Column("freesBytes").set(to: bytes))
        }
    }

    /// A count of all of the job's snapshots on the drive, which replaces anything known about them.
    func recordFullCount(ofJob jobID: UUID, onDrive driveUUID: String, usedBytes: Int64, freesBytes: [UUID: Int64]) throws {
        try database.writer.write { database in
            try Self.setUsedBytes(usedBytes, ofJob: jobID, onDrive: driveUUID, in: database)
            for (id, bytes) in freesBytes {
                try SnapshotRecord
                    .filter(key: id)
                    .updateAll(database, Column("isCounted").set(to: true), Column("freesBytes").set(to: bytes))
            }
        }
    }

    /// Takes a picked-up partial's files out of its job's space. When what it frees isn't known, the
    /// job's space isn't either, until it's counted again.
    static func uncount(_ record: SnapshotRecord, in database: Database) throws {
        let used = try usedBytes(ofJob: record.jobID, onDrive: record.driveUUID, in: database)
        let remaining = used.flatMap { used in record.freesBytes.map { used - $0 } }
        try setUsedBytes(remaining, ofJob: record.jobID, onDrive: record.driveUUID, in: database)
    }

    /// A snapshot whose folder has gone from the drive some other way. Its job is counted again, since
    /// what went with it isn't known.
    func forgetMissing(_ id: UUID) throws {
        try database.writer.write { database in
            guard let record = try SnapshotRecord.fetchOne(database, key: id) else { return }
            try Self.setUsedBytes(nil, ofJob: record.jobID, onDrive: record.driveUUID, in: database)
            try record.delete(database)
        }
    }

    static func usedBytes(ofJob jobID: UUID, onDrive driveUUID: String, in database: Database) throws -> Int64? {
        try Int64.fetchOne(database, sql: "SELECT usedBytes FROM jobSpace WHERE driveUUID = ? AND jobID = ?", arguments: [driveUUID, jobID])
    }

    static func setUsedBytes(_ bytes: Int64?, ofJob jobID: UUID, onDrive driveUUID: String, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO jobSpace (driveUUID, jobID, usedBytes) VALUES (?, ?, ?)
            ON CONFLICT (driveUUID, jobID) DO UPDATE SET usedBytes = excluded.usedBytes
            """,
            arguments: [driveUUID, jobID, bytes]
        )
    }
}
