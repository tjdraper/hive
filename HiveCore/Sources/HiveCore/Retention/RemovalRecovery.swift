import Foundation
import HiveKit
import os

/// Finishes removals a restart or a failure cut short, before anything is counted, since a half-removed
/// snapshot can't be.
struct RemovalRecovery {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Retention")

    let store: RetentionStore
    let removals: SnapshotRemovalStore
    let remover: SnapshotRemover
    let jobLog: JobLog
    let now: @Sendable () -> Date

    /// Returns what it logged.
    func finish(onDrive driveUUID: String, in hiveFolder: DriveFolder) throws -> [RemovalLogEntry] {
        var logged: [RemovalLogEntry] = []
        for record in try removals.unfinished(onDrive: driveUUID) {
            try Task.checkCancellation()
            // A job removed since keeps the folders the snapshot was found in, which still have to be
            // single names, opened without following links.
            let folders = try store.folders(ofJob: record.jobID) ?? SnapshotFolders(server: record.serverFolder, job: record.jobFolder)
            guard let jobFolder = RetentionWorkflow.openJobFolder(folders, in: hiveFolder) else { continue }
            do {
                let outcome = try remover.finishUnfinished(record, in: jobFolder, folders: folders, driveUUID: driveUUID)
                Self.logger.notice("Finished a removal cut short: \(String(describing: outcome), privacy: .public)")
                if case .removed(let bytesFreed) = outcome, let reason = record.removalReason {
                    let removed = RemovedSnapshot(
                        snapshotID: record.id,
                        date: record.date,
                        wasComplete: record.completedAt != nil,
                        reason: reason,
                        bytesFreed: bytesFreed
                    )
                    if let entry = try jobLog.recordRemovals(ofJob: record.jobID, removed: [removed], notRemoved: [], at: now()) {
                        logged.append(entry)
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.logger.error("Couldn't finish a removal: \(RetentionWorkflow.described(error), privacy: .public)")
            }
        }
        return logged
    }
}
