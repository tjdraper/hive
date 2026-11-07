import Darwin
import Foundation
import HiveKit

enum PartialSnapshotError: Error, Equatable {
    case couldNotCreate(errno: Int32)
    case couldNotRename(errno: Int32)
}

/// A snapshot being written: `<date-time>.partial` in its job's folder until every part of it is in,
/// then renamed (§9).
struct PartialSnapshot {
    let record: SnapshotRecord
    let url: URL
    /// Where each of the job's directories goes, under `files/`, in the job's order.
    let destinations: [URL]
    /// Left by a run that failed, rather than made by this one.
    let isPickedUp: Bool

    var jobFolder: URL {
        url.deletingLastPathComponent()
    }

    /// Written in place of the one before, never through a link standing in for it.
    func write(_ manifest: SnapshotManifest) throws {
        try manifest.encoded().write(to: url.appending(path: SnapshotManifest.fileName, directoryHint: .notDirectory), options: .atomic)
    }

    /// Removes the `databases/` folder a failed run left. Every run dumps each database whole, and the
    /// job may no longer have some of them.
    func removeDatabasesFolder() throws {
        let folder = url.appending(path: SnapshotManifest.databasesFolder, directoryHint: .isDirectory)
        var info = stat()
        // Removing a link removes only the link.
        if lstat(folder.fileSystemPath, &info) == 0 { try FileManager.default.removeItem(at: folder) }
    }

    /// Renames it to its final name, refusing to replace anything already there. Returns the name.
    func complete(at date: Date) throws -> String {
        let name = SnapshotFolderName.snapshot(at: date)
        let destination = jobFolder.appending(path: name, directoryHint: .isDirectory)
        guard renamex_np(url.fileSystemPath, destination.fileSystemPath, UInt32(RENAME_EXCL)) == 0 else {
            throw PartialSnapshotError.couldNotRename(errno: errno)
        }
        return name
    }
}

/// Picks up the partial snapshot a failed run left, or makes a new one, with a folder ready for each
/// of the job's directories.
struct PartialSnapshotFactory: Sendable {
    let catalog: SnapshotCatalog

    struct Job {
        let jobID: UUID
        let serverID: UUID
        let folders: SnapshotFolders
        /// Each directory's folder within `files/`, such as `images/galleries`.
        let directoryFolders: [String]
    }

    func prepare(_ job: Job, on drive: LocatedDrive, at date: Date) throws -> PartialSnapshot {
        let jobFolder = try RealFolder.make([job.folders.server, job.folders.job], under: drive.hiveFolder)

        for record in try catalog.snapshots(ofJob: job.jobID, onDrive: drive.identity.volumeUUID, in: .partial) {
            guard let url = RealFolder.existing([record.folder], under: jobFolder) else {
                try catalog.forget(record.id)
                continue
            }
            // A partial from before the job's directories changed is left for retention, and a new one
            // started: it could hold a directory the job no longer has, or a server's link where one of
            // the new directories needs a folder.
            if holdsOnly(job, in: url), let destinations = try? destinations(for: job, in: url) {
                try catalog.pickUp(record.id)
                return PartialSnapshot(record: record, url: url, destinations: destinations, isPickedUp: true)
            }
        }

        let record = SnapshotRecord(
            id: UUID(),
            jobID: job.jobID,
            serverID: job.serverID,
            driveUUID: drive.identity.volumeUUID.uuidString,
            serverFolder: job.folders.server,
            jobFolder: job.folders.job,
            folder: SnapshotFolderName.partial(at: date),
            state: .partial,
            startedAt: date,
            completedAt: nil
        )
        // In the catalog before it's on the drive, so nothing Hive makes there is ever unknown to it.
        try catalog.add(record)
        let url = jobFolder.appending(path: record.folder, directoryHint: .isDirectory)
        guard mkdir(url.fileSystemPath, 0o755) == 0 else {
            let error = errno
            try catalog.forget(record.id)
            throw PartialSnapshotError.couldNotCreate(errno: error)
        }
        return PartialSnapshot(record: record, url: url, destinations: try destinations(for: job, in: url), isPickedUp: false)
    }

    private func holdsOnly(_ job: Job, in snapshot: URL) -> Bool {
        let tops = Set(job.directoryFolders.compactMap { $0.split(separator: "/").first.map(String.init) })
        let files = snapshot.appending(path: "files", directoryHint: .isDirectory).fileSystemPath
        let present = (try? FileManager.default.contentsOfDirectory(atPath: files)) ?? []
        return present.allSatisfy(tops.contains)
    }

    private func destinations(for job: Job, in snapshot: URL) throws -> [URL] {
        try job.directoryFolders.map { folder in
            try RealFolder.make(["files"] + folder.split(separator: "/").map(String.init), under: snapshot)
        }
    }
}
