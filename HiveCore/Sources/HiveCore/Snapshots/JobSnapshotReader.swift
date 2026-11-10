import Foundation
import GRDB
import HiveKit

/// A job's snapshots on the chosen backup drive, as the catalog has them, for Beekeeper's list. A
/// removed job's are listed too, while it has any.
struct JobSnapshotReader: Sendable {
    private struct Read {
        let records: [SnapshotRecord]
        let usedBytes: Int64?
        /// Waiting for the queue to delete them.
        let deleting: Set<UUID>
    }

    let database: HiveDatabase
    let drives: BackupDriveLocator

    /// Nil when no job has that ID and the catalog has no snapshots of one that had.
    func snapshots(ofJob jobID: UUID) throws -> JobSnapshots? {
        let read = try database.writer.read { database -> Read? in
            let exists = try BackupJobRecord.exists(database, key: jobID)
            guard let drive = try BackupDriveStore.chosen(in: database) else {
                return exists ? Read(records: [], usedBytes: nil, deleting: []) : nil
            }
            let driveUUID = drive.volumeUUID.uuidString
            let records = try SnapshotRecord
                .filter(Column("jobID") == jobID && Column("driveUUID") == driveUUID)
                .order(SQL("COALESCE(completedAt, startedAt) DESC"))
                .fetchAll(database)
            guard exists || !records.isEmpty else { return nil }
            let deleting = try UUID.fetchAll(
                database,
                sql: "SELECT snapshotID FROM snapshotDeletion JOIN snapshot ON snapshot.id = snapshotID WHERE snapshot.jobID = ?",
                arguments: [jobID]
            )
            return Read(
                records: records,
                usedBytes: try SnapshotSpaceStore.usedBytes(ofJob: jobID, onDrive: driveUUID, in: database),
                deleting: Set(deleting)
            )
        }
        guard let read else { return nil }

        return JobSnapshots(
            snapshots: read.records.map { record in
                SnapshotSummary(
                    id: record.id,
                    date: record.date,
                    state: read.deleting.contains(record.id) ? .removing : Self.state(of: record),
                    folder: record.folder,
                    freesBytes: record.freesBytes
                )
            },
            folderPath: try read.records.first.flatMap(folderPath),
            usedBytes: read.usedBytes
        )
    }

    /// Only while the drive is mounted and marked as this Hive's, since otherwise its mount point is
    /// just a folder on the startup disk.
    private func folderPath(of record: SnapshotRecord) throws -> String? {
        guard case .ready(let drive) = try drives.locate() else { return nil }
        return drive.hiveFolder
            .appending(path: record.serverFolder, directoryHint: .isDirectory)
            .appending(path: record.jobFolder, directoryHint: .isDirectory)
            .fileSystemPath
    }

    private static func state(of record: SnapshotRecord) -> SnapshotSummary.State {
        switch record.state {
        case .complete: .complete
        case .partial: .partial
        case .removing: .removing
        }
    }
}
