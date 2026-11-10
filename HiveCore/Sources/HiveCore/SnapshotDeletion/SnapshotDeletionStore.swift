import Foundation
import GRDB
import HiveKit

/// What a device asked to delete.
enum SnapshotDeletionScope: Equatable {
    case snapshot(UUID)
    /// Every snapshot of the job, removed or not.
    case job(UUID)
    /// Every snapshot of the server's, its removed jobs' included.
    case server(UUID)
}

enum SnapshotDeletionRequest: Equatable {
    case requested(count: Int)
    /// Nothing to delete on the chosen backup drive.
    case nothingToDelete
    /// It includes a partial snapshot a run is writing to now.
    case beingWritten
}

/// Deletions a device asked for, kept in the store until the queue gets to them (§10). Asking records
/// the snapshots as they are then, so one made afterwards is never included.
struct SnapshotDeletionStore: Sendable {
    let database: HiveDatabase

    /// Throws `ConfirmationError.required`, recording nothing, unless confirmed. Recorded in the audit log.
    func request(_ scope: SnapshotDeletionScope, isConfirmed: Bool, by deviceID: UUID, at date: Date) throws -> SnapshotDeletionRequest {
        try database.writer.write { database in
            guard let drive = try BackupDriveStore.chosen(in: database) else { return .nothingToDelete }
            let snapshots = try Self.snapshots(in: scope, onDrive: drive.volumeUUID.uuidString, in: database)
            guard !snapshots.isEmpty else { return .nothingToDelete }
            try ConfirmationRequirement.check([.snapshotsDeleted], isConfirmed: isConfirmed)

            let running = try Set(UUID.fetchAll(database, sql: "SELECT jobID FROM queuedRun WHERE logEntryID IS NOT NULL"))
            if snapshots.contains(where: { $0.state == .partial && running.contains($0.jobID) }) { return .beingWritten }

            for snapshot in snapshots {
                try database.execute(
                    sql: "INSERT INTO snapshotDeletion (snapshotID, requestedAt) VALUES (?, ?) ON CONFLICT (snapshotID) DO NOTHING",
                    arguments: [snapshot.id, date]
                )
            }
            let deletion = try Self.audited(scope, snapshots: snapshots, in: database)
            try AuditLog.record(.snapshotsDeleted(deletion), by: deviceID, at: date, in: database)
            return .requested(count: snapshots.count)
        }
    }

    func hasPending() throws -> Bool {
        try database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM snapshotDeletion") ?? 0 > 0 }
    }

    /// The snapshots waiting to be deleted from the drive, oldest first.
    func pending(onDrive driveUUID: String) throws -> [SnapshotRecord] {
        try database.writer.read { database in
            try SnapshotRecord.fetchAll(database, sql: """
            SELECT snapshot.* FROM snapshot JOIN snapshotDeletion ON snapshotDeletion.snapshotID = snapshot.id
            WHERE snapshot.driveUUID = ?
            ORDER BY COALESCE(snapshot.completedAt, snapshot.startedAt)
            """, arguments: [driveUUID])
        }
    }

    /// Once it's deleted, or couldn't be. A snapshot that's gone takes its request with it.
    func finish(_ snapshotID: UUID) throws {
        try database.writer.write { try $0.execute(sql: "DELETE FROM snapshotDeletion WHERE snapshotID = ?", arguments: [snapshotID]) }
    }

    /// Those on the drive that aren't being removed already.
    private static func snapshots(
        in scope: SnapshotDeletionScope,
        onDrive driveUUID: String,
        in database: Database
    ) throws -> [SnapshotRecord] {
        let onDrive = SnapshotRecord
            .filter(Column("driveUUID") == driveUUID)
            .filter(Column("state") != SnapshotState.removing.rawValue)
        return switch scope {
        case .snapshot(let id): try onDrive.filter(key: id).fetchAll(database)
        case .job(let id): try onDrive.filter(Column("jobID") == id).fetchAll(database)
        case .server(let id): try onDrive.filter(Column("serverID") == id).fetchAll(database)
        }
    }

    /// `snapshots` isn't empty, so their catalog entries always give a name.
    private static func audited(
        _ scope: SnapshotDeletionScope,
        snapshots: [SnapshotRecord],
        in database: Database
    ) throws -> SnapshotDeletion {
        switch scope {
        case .snapshot:
            let snapshot = snapshots[0]
            let names = try JobNames.lastKnown(jobID: snapshot.jobID, in: database)
            return .snapshot(jobID: snapshot.jobID, serverName: names?.server ?? "", jobName: names?.job ?? "", date: snapshot.date)
        case .job(let id):
            let names = try JobNames.lastKnown(jobID: id, in: database)
            return .job(jobID: id, serverName: names?.server ?? "", jobName: names?.job ?? "", count: snapshots.count)
        case .server(let id):
            return .server(serverID: id, serverName: try JobNames.lastKnownServerName(id, in: database) ?? "", count: snapshots.count)
        }
    }
}
