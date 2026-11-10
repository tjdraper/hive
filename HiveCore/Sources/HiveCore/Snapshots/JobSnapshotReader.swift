import Foundation
import GRDB
import HiveKit

/// A job's snapshots on the chosen backup drive, as the catalog has them, for Beekeeper's list.
struct JobSnapshotReader: Sendable {
    let database: HiveDatabase
    let drives: BackupDriveLocator

    /// Nil when no job has that ID.
    func snapshots(ofJob jobID: UUID) throws -> JobSnapshots? {
        let read = try database.writer.read { database -> (records: [SnapshotRecord], usedBytes: Int64?)? in
            guard try BackupJobRecord.exists(database, key: jobID) else { return nil }
            guard let drive = try BackupDriveStore.chosen(in: database) else { return ([], nil) }
            let driveUUID = drive.volumeUUID.uuidString
            let records = try SnapshotRecord
                .filter(Column("jobID") == jobID && Column("driveUUID") == driveUUID)
                .order(SQL("COALESCE(completedAt, startedAt) DESC"))
                .fetchAll(database)
            return (records, try SnapshotSpaceStore.usedBytes(ofJob: jobID, onDrive: driveUUID, in: database))
        }
        guard let read else { return nil }

        return JobSnapshots(
            snapshots: read.records.map { record in
                SnapshotSummary(
                    id: record.id,
                    date: record.date,
                    state: Self.state(of: record),
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
