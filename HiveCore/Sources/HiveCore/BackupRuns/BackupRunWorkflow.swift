import Foundation
import HiveKit
import os

/// One run of a backup job (§9): find the drive, check the server's directories, pull each into a
/// partial snapshot, then write its manifest and complete it. A run that fails leaves its partial
/// snapshot for the next run to pick up. Directories only, until C4 adds database dumps.
struct BackupRunWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Backup")

    /// Ends a run early with the reason it failed.
    private struct Stop: Error {
        let failure: BackupFailure
    }

    let hiveID: UUID
    let database: HiveDatabase
    let drives: BackupDriveLocator
    let targets: SSHTargetLoader
    let rsync: RsyncRunner
    /// The server for each run, or in tests, folders on this Mac.
    let origin: @Sendable (SSHTarget) -> RsyncOrigin
    let now: @Sendable () -> Date

    private var catalog: SnapshotCatalog {
        SnapshotCatalog(database: database)
    }

    /// Nil when no job has that ID. `progress` gets the run as each directory finishes. Off the caller's
    /// actor, since a run takes minutes.
    @concurrent func run(jobID: UUID, progress: @Sendable (BackupRun) async -> Void) async throws -> BackupRun? {
        guard let job = try BackupJobStore(database: database).job(id: jobID),
              let server = try ServerStore(database: database).server(id: job.serverID)
        else { return nil }

        let startedAt = now()
        let clock = ContinuousClock.now
        Self.logger.notice("Started a run with \(job.directories.count, privacy: .public) directories")

        var directories: [DirectoryRun] = []
        var failure: BackupFailure?
        do {
            try await perform(job, on: server, startedAt: startedAt) { directory in
                directories.append(directory)
                await progress(BackupRun(jobID: jobID, startedAt: startedAt, finishedAt: nil, failure: nil, directories: directories))
            }
        } catch let stop as Stop {
            failure = stop.failure
        } catch is CancellationError {
            failure = .cancelled
        } catch {
            Self.logger.error("The run stopped on \(String(describing: type(of: error)), privacy: .public)")
            failure = .failed
        }

        let seconds = (ContinuousClock.now - clock).roundedSeconds
        if let failure {
            Self.logger.error("The run failed after \(seconds, privacy: .public)s: \(failure.rawValue, privacy: .public)")
        } else {
            Self.logger.notice("The run completed its snapshot in \(seconds, privacy: .public)s")
        }
        return BackupRun(jobID: jobID, startedAt: startedAt, finishedAt: now(), failure: failure, directories: directories)
    }

    private func perform(
        _ job: BackupJob,
        on server: Server,
        startedAt: Date,
        pulled: (DirectoryRun) async -> Void
    ) async throws {
        let drive = try locateDrive()
        let origin = try origin(for: server)

        if let problem = try await SourceCheck(rsync: rsync).problem(with: job.directories, from: origin) {
            throw Stop(failure: problem)
        }

        let partial = try onDrive {
            let folders = try SnapshotFolderResolver(database: database).folders(
                serverID: server.id, serverName: server.name, jobID: job.id, jobName: job.name, in: drive.hiveFolder
            )
            let request = PartialSnapshotFactory.Job(
                jobID: job.id, serverID: server.id, folders: folders, directoryFolders: job.directories.map(\.folder)
            )
            return try PartialSnapshotFactory(catalog: catalog).prepare(request, on: drive, at: startedAt)
        }
        let start = partial.isPickedUp ? "Picked up the partial snapshot a failed run left" : "Started a new snapshot"
        Self.logger.notice("\(start, privacy: .public)")
        let previous = try previousSnapshot(of: job, on: drive, folder: partial.jobFolder)

        var copied: [SnapshotManifest.Directory] = []
        try onDrive { try partial.write(manifest(job, server: server, partial: partial, directories: copied, completedAt: nil)) }

        let pull = DirectoryPull(rsync: rsync)
        for (directory, destination) in zip(job.directories, partial.destinations) {
            let parts = ["files"] + directory.folder.split(separator: "/").map(String.init)
            let linkTo = previous.flatMap { RealFolder.existing(parts, under: $0) }
            let report = try await pull.pull(directory, from: origin, into: destination, linkingTo: linkTo)
            await pulled(report)
            if let failure = report.failure { throw Stop(failure: failure) }
            copied.append(SnapshotManifest.Directory(path: directory.path, folder: directory.folder, vanishedFiles: report.vanishedFiles))
            try onDrive { try partial.write(manifest(job, server: server, partial: partial, directories: copied, completedAt: nil)) }
        }

        let completedAt = now()
        try onDrive {
            try partial.write(manifest(job, server: server, partial: partial, directories: copied, completedAt: completedAt))
            let name = try partial.complete(at: completedAt)
            try catalog.markComplete(partial.record.id, folder: name, at: completedAt)
        }
    }

    private func locateDrive() throws -> LocatedDrive {
        switch try drives.locate() {
        case .ready(let drive):
            return drive
        case .unavailable(let failure):
            throw Stop(failure: failure)
        }
    }

    private func origin(for server: Server) throws -> RsyncOrigin {
        switch try targets.target(forServer: server.id) {
        case .ready(let target):
            return origin(target)
        case .unavailable(let reason):
            throw Stop(failure: BackupFailure(reason))
        case nil:
            throw Stop(failure: .failed)
        }
    }

    /// The job's newest complete snapshot still on the drive, for unchanged files to link to.
    private func previousSnapshot(of job: BackupJob, on drive: LocatedDrive, folder jobFolder: URL) throws -> URL? {
        let complete = try catalog.snapshots(ofJob: job.id, onDrive: drive.identity.volumeUUID, in: .complete)
        return complete.lazy.compactMap { RealFolder.existing([$0.folder], under: jobFolder) }.first
    }

    private func manifest(
        _ job: BackupJob,
        server: Server,
        partial: PartialSnapshot,
        directories: [SnapshotManifest.Directory],
        completedAt: Date?
    ) -> SnapshotManifest {
        SnapshotManifest(
            format: SnapshotManifest.currentFormat,
            hiveID: hiveID,
            snapshotID: partial.record.id,
            server: .init(id: server.id, name: server.name),
            job: .init(id: job.id, name: job.name),
            startedAt: partial.record.startedAt,
            completedAt: completedAt,
            complete: completedAt != nil,
            directories: directories
        )
    }

    /// Anything that goes wrong writing to the drive stops the run as one failure.
    private func onDrive<Value>(_ body: () throws -> Value) throws -> Value {
        do {
            return try body()
        } catch {
            Self.logger.error("Couldn't write the snapshot: \(String(describing: type(of: error)), privacy: .public)")
            throw Stop(failure: .couldNotWriteSnapshot)
        }
    }
}
