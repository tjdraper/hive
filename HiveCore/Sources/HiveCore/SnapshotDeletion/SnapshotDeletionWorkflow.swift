import Foundation
import HiveKit
import os

/// Deletes the snapshots devices asked to delete, through `SnapshotRemover`, so each goes the same
/// careful way retention's do. It runs on the job queue, ahead of waiting runs, so nothing it touches
/// is being written and a run never picks up a partial snapshot that's about to go.
///
/// Each request is settled once it's tried: deleted, already gone, or logged as not deleted. Only a
/// missing backup drive leaves them waiting, for the next time the queue is free.
struct SnapshotDeletionWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Retention")

    private enum JobFolderLookup {
        case open(DriveFolder)
        case missing
        case unusable
    }

    let drives: BackupDriveLocator
    let deletions: SnapshotDeletionStore
    let retention: RetentionStore
    let remover: SnapshotRemover
    let space: SnapshotSpaceStore
    let jobLog: JobLog
    let now: @Sendable () -> Date

    init(database: HiveDatabase, drives: BackupDriveLocator, remover: SnapshotRemover, now: @escaping @Sendable () -> Date) {
        self.drives = drives
        deletions = SnapshotDeletionStore(database: database)
        retention = RetentionStore(database: database)
        self.remover = remover
        space = SnapshotSpaceStore(database: database)
        jobLog = JobLog(database: database)
        self.now = now
    }

    /// Returns what it logged.
    @concurrent func run() async -> [RemovalLogEntry] {
        guard (try? deletions.hasPending()) == true else { return [] }
        guard case .ready(let drive) = (try? drives.locate()) ?? .unavailable(.failed) else {
            Self.logger.notice("Deletions wait: the backup drive isn't available")
            return []
        }

        var removed: [UUID: [RemovedSnapshot]] = [:]
        var notRemoved: [UUID: [UnremovedSnapshot]] = [:]
        do {
            let hiveFolder = try DriveFolder(at: drive.hiveFolder)
            let driveUUID = drive.identity.volumeUUID.uuidString
            for record in try deletions.pending(onDrive: driveUUID) {
                try Task.checkCancellation()
                switch try delete(record, driveUUID: driveUUID, in: hiveFolder) {
                case .removed(let bytesFreed):
                    removed[record.jobID, default: []].append(RemovedSnapshot(
                        snapshotID: record.id,
                        date: record.date,
                        wasComplete: record.state == .complete,
                        reason: .deletedByDevice,
                        bytesFreed: bytesFreed
                    ))
                case .refused(let problem):
                    Self.logger.error("Didn't delete a snapshot: \(problem.rawValue, privacy: .public)")
                    notRemoved[record.jobID, default: []].append(UnremovedSnapshot(
                        snapshotID: record.id,
                        date: record.date,
                        wasComplete: record.state == .complete,
                        reason: .deletedByDevice,
                        problem: problem
                    ))
                case .missing:
                    break
                }
                try deletions.finish(record.id)
            }
        } catch is CancellationError {
            Self.logger.notice("Deletions stopped part way, as Hive stops")
        } catch {
            Self.logger.error("Deletions stopped on \(RetentionWorkflow.described(error), privacy: .public)")
        }

        Self.logger.notice("Deleted \(removed.values.joined().count, privacy: .public) snapshots devices asked to delete")
        return log(removed: removed, notRemoved: notRemoved)
    }

    /// An entry for each job, with what was deleted and what wasn't. Returns them.
    private func log(removed: [UUID: [RemovedSnapshot]], notRemoved: [UUID: [UnremovedSnapshot]]) -> [RemovalLogEntry] {
        Set(removed.keys).union(notRemoved.keys).compactMap { jobID in
            do {
                let notRemoved = notRemoved[jobID] ?? []
                return try jobLog.recordRemovals(ofJob: jobID, removed: removed[jobID] ?? [], notRemoved: notRemoved, at: now())
            } catch {
                Self.logger.error("Couldn't record deletions in the job log: \(RetentionWorkflow.described(error), privacy: .public)")
                return nil
            }
        }
    }

    /// Throws only when the task is cancelled, which leaves a removal under way for retention's next pass to finish.
    private func delete(_ record: SnapshotRecord, driveUUID: String, in hiveFolder: DriveFolder) throws -> SnapshotRemover.Outcome {
        // One retention started removing is finished by its next pass.
        guard record.state != .removing else { return .missing }
        do {
            // A removed job keeps the folders its snapshots were found in, which still have to be single
            // names, opened without following links.
            let folders = try retention.folders(ofJob: record.jobID) ?? SnapshotFolders(server: record.serverFolder, job: record.jobFolder)
            switch jobFolder(folders, in: hiveFolder) {
            case .open(let jobFolder):
                return try remover.remove(record, because: .deletedByDevice, in: jobFolder, folders: folders, driveUUID: driveUUID)
            case .missing:
                try space.forgetMissing(record.id)
                return .missing
            case .unusable:
                return .refused(.notInJobFolder)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("Couldn't delete a snapshot: \(RetentionWorkflow.described(error), privacy: .public)")
            return .refused(.couldNotRemove)
        }
    }

    private func jobFolder(_ folders: SnapshotFolders, in hiveFolder: DriveFolder) -> JobFolderLookup {
        do {
            guard try hiveFolder.contains(folders.server) else { return .missing }
            let serverFolder = try DriveFolder(name: folders.server, in: hiveFolder)
            guard try serverFolder.contains(folders.job) else { return .missing }
            return .open(try DriveFolder(name: folders.job, in: serverFolder))
        } catch {
            Self.logger.error("Couldn't open a job's folder on the drive: \(RetentionWorkflow.described(error), privacy: .public)")
            return .unusable
        }
    }
}
