import Foundation
import GRDB
import HiveKit

/// A removal's steps in the catalog. It's recorded before anything on the drive changes, with what it
/// will free, so a removal cut short is finished on the next pass and its space taken off once.
struct SnapshotRemovalStore: Sendable {
    let database: HiveDatabase

    /// Whether a run is writing to the job's snapshots now.
    func isRunning(jobID: UUID) throws -> Bool {
        try database.writer.read { database in
            try QueuedRunRecord.filter(key: jobID).filter(Column("logEntryID") != nil).fetchCount(database) > 0
        }
    }

    /// False when it's no longer partial or complete, such as when a run picked it up or completed it
    /// since it was read.
    func begin(_ id: UUID, freesBytes: Int64, reason: RemovalReason) throws -> Bool {
        try database.writer.write { database in
            guard var record = try SnapshotRecord.fetchOne(database, key: id), record.state != .removing else { return false }
            record.state = .removing
            record.freesBytes = freesBytes
            record.removalReason = reason
            try record.update(database)
            return true
        }
    }

    /// Its folder is gone: forgets it, takes what it freed off its job's space, and marks what its
    /// nearest snapshots free as unknown, since files they shared with it may now be theirs alone.
    func finish(_ id: UUID) throws {
        try database.writer.write { database in
            guard let record = try SnapshotRecord.fetchOne(database, key: id), record.state == .removing else { return }
            if record.isCounted, let freed = record.freesBytes,
               let used = try SnapshotSpaceStore.usedBytes(ofJob: record.jobID, onDrive: record.driveUUID, in: database) {
                try SnapshotSpaceStore.setUsedBytes(used - freed, ofJob: record.jobID, onDrive: record.driveUUID, in: database)
            } else {
                try SnapshotSpaceStore.setUsedBytes(nil, ofJob: record.jobID, onDrive: record.driveUUID, in: database)
            }
            try record.delete(database)

            let others = try SnapshotRecord
                .filter(Column("jobID") == record.jobID && Column("driveUUID") == record.driveUUID)
                .filter(Column("state") != SnapshotState.removing.rawValue)
                .fetchAll(database)
            let complete = others.filter { $0.state == .complete }
            let neighbors = [
                complete.filter { $0.date < record.date }.max { $0.date < $1.date },
                complete.filter { $0.date >= record.date }.min { $0.date < $1.date },
            ].compactMap(\.?.id) + others.filter { $0.state == .partial }.map(\.id)
            try SnapshotRecord.filter(keys: neighbors).updateAll(database, Column("freesBytes").set(to: nil))
        }
    }

    /// Removals cut short, on the drive.
    func unfinished(onDrive driveUUID: String) throws -> [SnapshotRecord] {
        try database.writer.read { database in
            try SnapshotRecord
                .filter(Column("driveUUID") == driveUUID && Column("state") == SnapshotState.removing.rawValue)
                .fetchAll(database)
        }
    }
}
