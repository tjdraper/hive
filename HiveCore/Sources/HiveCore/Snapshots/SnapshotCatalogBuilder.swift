import Darwin
import Foundation
import GRDB
import HiveKit
import os

/// Rebuilds the catalog from the snapshots on a backup drive (§9), taking over every one whose manifest
/// carries this Hive's ID: after a restore, when Hive's store was lost, or when the drive came back from a
/// Mac backup with a new volume UUID. A snapshot already cataloged on another drive moves to this one.
///
/// What it takes over starts uncounted, and its job's space unknown, so the next retention pass counts
/// each job whole. Taking any over pauses retention until a device starts it again (§10): a drive
/// restored from a Mac backup may have lost its hard links, and its space would then remove history.
struct SnapshotCatalogBuilder: Sendable {
    /// Far more than a manifest needs, so a stray large file is never read whole.
    static let largestManifest = 1 << 20

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Snapshots")

    struct Outcome: Equatable {
        /// Complete and partial snapshots the catalog now has on the drive that it didn't before.
        var takenOver = 0
        /// Cataloged already.
        var known = 0
        /// Whose manifest is another Hive's, unreadable, or doesn't match its folder.
        var skipped = 0
    }

    let database: HiveDatabase
    let hiveID: UUID
    let now: @Sendable () -> Date

    func takeOver(_ drive: LocatedDrive) throws -> Outcome {
        let clock = ContinuousClock.now
        let driveUUID = drive.identity.volumeUUID.uuidString
        var found: [SnapshotRecord] = []
        var skipped = 0
        for serverFolder in Self.realFolders(in: drive.hiveFolder) {
            let server = drive.hiveFolder.appending(path: serverFolder, directoryHint: .isDirectory)
            for jobFolder in Self.realFolders(in: server) {
                let job = server.appending(path: jobFolder, directoryHint: .isDirectory)
                for folder in Self.realFolders(in: job) where SnapshotFolderName.isSnapshot(folder) {
                    let url = job.appending(path: folder, directoryHint: .isDirectory)
                    let folders = SnapshotFolders(server: serverFolder, job: jobFolder)
                    guard let record = record(for: url, driveUUID: driveUUID, folders: folders, folder: folder) else {
                        skipped += 1
                        continue
                    }
                    found.append(record)
                }
            }
        }

        let date = now()
        var outcome = try database.writer.write { database in
            let outcome = try Self.catalog(found, onDrive: driveUUID, in: database)
            if outcome.takenOver > 0 {
                try database.execute(sql: "UPDATE hive SET retentionPausedSince = COALESCE(retentionPausedSince, ?)", arguments: [date])
            }
            return outcome
        }
        outcome.skipped = skipped
        let seconds = (ContinuousClock.now - clock).roundedSeconds
        Self.logger.notice("""
        Took over \(outcome.takenOver, privacy: .public) snapshots from the backup drive, \
        \(outcome.known, privacy: .public) known already, \(outcome.skipped, privacy: .public) skipped, \
        in \(seconds, privacy: .public)s
        """)
        return outcome
    }

    private func record(for url: URL, driveUUID: String, folders: SnapshotFolders, folder: String) -> SnapshotRecord? {
        guard let manifest = Self.readManifest(in: url), manifest.format == SnapshotManifest.currentFormat,
              manifest.hiveID == hiveID
        else { return nil }
        let isPartial = folder.hasSuffix(SnapshotFolderName.partialSuffix)
        // A run writes its last manifest just before renaming its folder, so a complete manifest in a
        // partial folder is a run cut short between the two, and the next run carries on with it.
        guard isPartial || manifest.complete else { return nil }
        return SnapshotRecord(
            id: manifest.snapshotID,
            jobID: manifest.job.id,
            serverID: manifest.server.id,
            driveUUID: driveUUID,
            serverFolder: folders.server,
            jobFolder: folders.job,
            folder: folder,
            state: isPartial ? .partial : .complete,
            startedAt: manifest.startedAt,
            completedAt: isPartial ? nil : manifest.completedAt ?? manifest.startedAt
        )
    }

    private static func catalog(_ found: [SnapshotRecord], onDrive driveUUID: String, in database: Database) throws -> Outcome {
        var outcome = Outcome()
        var changedJobs: Set<UUID> = []
        for record in found {
            let sameFolder = try SnapshotRecord
                .filter(Column("driveUUID") == driveUUID)
                .filter(Column("serverFolder") == record.serverFolder && Column("jobFolder") == record.jobFolder)
                .filter(Column("folder") == record.folder)
                .fetchOne(database)
            if sameFolder != nil {
                outcome.known += 1
                continue
            }
            if let elsewhere = try SnapshotRecord.fetchOne(database, key: record.id) {
                // The same snapshot, such as on the drive this one was restored from. Its space there is
                // no longer known.
                try SnapshotSpaceStore.setUsedBytes(nil, ofJob: elsewhere.jobID, onDrive: elsewhere.driveUUID, in: database)
                try elsewhere.delete(database)
            }
            try record.insert(database)
            changedJobs.insert(record.jobID)
            outcome.takenOver += 1
        }
        for jobID in changedJobs {
            try SnapshotSpaceStore.setUsedBytes(nil, ofJob: jobID, onDrive: driveUUID, in: database)
        }
        return outcome
    }

    /// The names of the real folders in `url`, never a link standing in for one. Empty when it can't be read.
    private static func realFolders(in url: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.fileSystemPath)) ?? []
        return names.sorted().filter { name in
            !name.hasPrefix(".") && RealFolder.exists(url.appending(path: name, directoryHint: .isDirectory))
        }
    }

    private static func readManifest(in snapshot: URL) -> SnapshotManifest? {
        let path = snapshot.appending(path: SnapshotManifest.fileName, directoryHint: .notDirectory).fileSystemPath
        // O_NOFOLLOW, so a link can't stand in for the manifest.
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard let data = try? handle.read(upToCount: largestManifest) else { return nil }
        return try? SnapshotManifest.decoded(from: data)
    }
}
