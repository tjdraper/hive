import Foundation
import HiveKit

/// Removes one snapshot from the backup drive, and nothing else, ever (§10).
///
/// It removes a snapshot only when the catalog has it, its folder is a real folder with a snapshot's
/// name inside its own job's folder on the located drive, and no run is writing to its job. Every step
/// goes through folders held open without following links, so neither a link nor a name in the catalog
/// can lead anywhere else. The folder is renamed before anything in it goes, and the catalog records the
/// removal first, so one cut short is finished later instead of leaving half a snapshot that looks whole.
struct SnapshotRemover: Sendable {
    enum Outcome: Equatable {
        case removed(bytesFreed: Int64)
        /// Its folder had already gone, so there was nothing to remove. The catalog forgets it.
        case missing
        case refused(RemovalProblem)
    }

    let removals: SnapshotRemovalStore
    let space: SnapshotSpaceStore

    /// `jobFolder` is the job's folder, opened from `folders`, the names its job and server were given
    /// on the drive identified by `driveUUID`.
    func remove(
        _ record: SnapshotRecord,
        because reason: RemovalReason,
        in jobFolder: DriveFolder,
        folders: SnapshotFolders,
        driveUUID: String
    ) throws -> Outcome {
        guard record.state != .removing else { return .refused(.couldNotRemove) }
        guard belongs(record, to: folders, driveUUID: driveUUID) else { return .refused(.notInJobFolder) }
        guard try !removals.isRunning(jobID: record.jobID) else { return .refused(.beingWritten) }
        guard try jobFolder.contains(record.folder) else {
            try space.forgetMissing(record.id)
            return .missing
        }

        guard let snapshot = try? DriveFolder(name: record.folder, in: jobFolder) else { return .refused(.notInJobFolder) }
        let freed = try snapshot.tally().exclusiveBytes
        guard try removals.begin(record.id, freesBytes: freed, reason: reason) else { return .refused(.couldNotRemove) }
        try jobFolder.rename(record.folder, to: SnapshotFolderName.removing(record.folder))
        return try finish(record.id, named: SnapshotFolderName.removing(record.folder), in: jobFolder, freed: freed)
    }

    /// Finishes a removal cut short, wherever it got to.
    func finishUnfinished(
        _ record: SnapshotRecord,
        in jobFolder: DriveFolder,
        folders: SnapshotFolders,
        driveUUID: String
    ) throws -> Outcome {
        guard record.state == .removing else { return .refused(.couldNotRemove) }
        guard belongs(record, to: folders, driveUUID: driveUUID) else { return .refused(.notInJobFolder) }
        let removing = SnapshotFolderName.removing(record.folder)
        if try !jobFolder.contains(removing), try jobFolder.contains(record.folder) {
            try jobFolder.rename(record.folder, to: removing)
        }
        return try finish(record.id, named: removing, in: jobFolder, freed: record.freesBytes ?? 0)
    }

    private func finish(_ id: UUID, named folder: String, in jobFolder: DriveFolder, freed: Int64) throws -> Outcome {
        if try jobFolder.contains(folder) {
            guard (try? DriveFolder(name: folder, in: jobFolder)) != nil else { return .refused(.notInJobFolder) }
            try jobFolder.removeFolder(folder)
        }
        try removals.finish(id)
        return .removed(bytesFreed: freed)
    }

    private func belongs(_ record: SnapshotRecord, to folders: SnapshotFolders, driveUUID: String) -> Bool {
        record.driveUUID == driveUUID
            && record.serverFolder == folders.server
            && record.jobFolder == folders.job
            && SnapshotFolderName.isSnapshot(record.folder)
    }
}
