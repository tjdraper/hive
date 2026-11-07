import Foundation
import os

/// Brings a job's space on the drive up to date, walking as few snapshots as it can, since a full
/// count of large trees over USB can take hours (§10).
///
/// After a run only the snapshot it wrote is uncounted. Its files that no other snapshot links to are
/// what the run added, so counting it alone keeps the job's space exact. When more than one is
/// uncounted they may share files none of the others has, which counting either alone would miss, so
/// the whole job is counted, as it is the first time.
struct SnapshotSpaceCounter: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Retention")

    let space: SnapshotSpaceStore
    let store: RetentionStore

    /// `jobFolder` holds the job's snapshots on the drive, and no run is writing to them.
    func update(jobID: UUID, driveUUID: String, folders: SnapshotFolders, in jobFolder: DriveFolder) throws {
        let clock = ContinuousClock.now
        var present: [SnapshotRecord] = []
        for snapshot in try ownSnapshots(jobID: jobID, driveUUID: driveUUID, folders: folders) {
            if try jobFolder.contains(snapshot.folder) {
                present.append(snapshot)
            } else {
                Self.logger.notice("A snapshot's folder had gone from the drive, so the catalog forgets it")
                try space.forgetMissing(snapshot.id)
            }
        }

        var walked = 0
        let uncounted = present.filter { !$0.isCounted }
        if try space.usedBytes(ofJob: jobID, onDrive: driveUUID) == nil || uncounted.count > 1 {
            try countAll(present, jobID: jobID, driveUUID: driveUUID, in: jobFolder)
            walked = present.count
        } else {
            if let snapshot = uncounted.first {
                try space.recordCount(of: snapshot.id, freesBytes: DriveFolder(name: snapshot.folder, in: jobFolder).tally().exclusiveBytes)
                walked += 1
            }
            for snapshot in try ownSnapshots(jobID: jobID, driveUUID: driveUUID, folders: folders)
                where snapshot.isCounted && snapshot.freesBytes == nil {
                try space.recordFreesBytes(DriveFolder(name: snapshot.folder, in: jobFolder).tally().exclusiveBytes, of: snapshot.id)
                walked += 1
            }
        }
        if walked > 0 {
            let seconds = (ContinuousClock.now - clock).roundedSeconds
            Self.logger.notice("Counted \(walked, privacy: .public) of a job's snapshots in \(seconds, privacy: .public)s")
        }
    }

    /// The job's snapshots in its own folder. Any other entry the catalog has for it is left alone.
    func ownSnapshots(jobID: UUID, driveUUID: String, folders: SnapshotFolders) throws -> [SnapshotRecord] {
        try store.snapshots(ofJob: jobID, onDrive: driveUUID).filter {
            $0.serverFolder == folders.server && $0.jobFolder == folders.job && SnapshotFolderName.isSnapshot($0.folder)
        }
    }

    private func countAll(_ snapshots: [SnapshotRecord], jobID: UUID, driveUUID: String, in jobFolder: DriveFolder) throws {
        var singleBytes: Int64 = 0
        var linked: [UInt64: Int64] = [:]
        var freesBytes: [UUID: Int64] = [:]
        for snapshot in snapshots {
            let tally = try DriveFolder(name: snapshot.folder, in: jobFolder).tally()
            singleBytes += tally.singleBytes
            for (inode, file) in tally.linked { linked[inode] = file.bytes }
            freesBytes[snapshot.id] = tally.exclusiveBytes
        }
        let usedBytes = linked.values.reduce(singleBytes, +)
        try space.recordFullCount(ofJob: jobID, onDrive: driveUUID, usedBytes: usedBytes, freesBytes: freesBytes)
    }
}
