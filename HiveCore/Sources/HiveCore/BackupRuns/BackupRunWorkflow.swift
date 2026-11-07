import Foundation
import HiveKit
import os

/// One run of a backup job (§9): find the drive, check the server's directories, pull each into a
/// partial snapshot, dump each database into it, then write its manifest and complete it. A run that
/// fails leaves its partial snapshot for the next run to pick up.
struct BackupRunWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Backup")

    /// Ends a run early with the reason it failed.
    private struct Stop: Error {
        let failure: BackupFailure
    }

    /// What a run tells whoever started it, as it goes.
    enum Report: Sendable {
        case step(RunStep)
        /// The run so far, each time a directory or database finishes.
        case progress(BackupRun)
    }

    private enum Step {
        case snapshotReady(pickedUp: Bool)
        case started(RunStep)
        case pulled(DirectoryRun)
        case dumped(DatabaseRun)
    }

    /// The run as far as it has got.
    private struct RunSoFar {
        let jobID: UUID
        let startedAt: Date
        var directories: [DirectoryRun] = []
        var databases: [DatabaseRun] = []
        var pickedUp = false
        var failure: BackupFailure?

        func run(finishedAt: Date?) -> BackupRun {
            BackupRun(
                jobID: jobID,
                startedAt: startedAt,
                finishedAt: finishedAt,
                failure: failure,
                directories: directories,
                databases: databases,
                pickedUpPartialSnapshot: pickedUp
            )
        }

        /// What to report about the step, if anything.
        mutating func take(_ step: Step) -> Report? {
            switch step {
            case .snapshotReady(let pickedUpPartial):
                pickedUp = pickedUpPartial
                return nil
            case .started(let step):
                return .step(step)
            case .pulled(let directory):
                directories.append(directory)
            case .dumped(let database):
                databases.append(database)
            }
            return .progress(run(finishedAt: nil))
        }
    }

    /// What a partial snapshot holds so far, for its manifest.
    private struct SnapshotContents {
        var directories: [SnapshotManifest.Directory] = []
        var databases: [SnapshotManifest.Database] = []
    }

    let hiveID: UUID
    let database: HiveDatabase
    let drives: BackupDriveLocator
    let targets: SSHTargetLoader
    let rsync: RsyncRunner
    let dumps: DatabaseDumpRunner
    let passwords: DatabasePasswordLoader
    /// The server for each run, or in tests, folders and scripts on this Mac.
    let origin: @Sendable (SSHTarget) -> BackupOrigin
    let now: @Sendable () -> Date

    private var catalog: SnapshotCatalog {
        SnapshotCatalog(database: database)
    }

    /// Nil when no job has that ID. Off the caller's actor, since a run takes minutes.
    @concurrent func run(jobID: UUID, report: @Sendable (Report) async -> Void) async throws -> BackupRun? {
        guard let job = try BackupJobStore(database: database).job(id: jobID),
              let server = try ServerStore(database: database).server(id: job.serverID)
        else { return nil }

        let startedAt = now()
        let clock = ContinuousClock.now
        let (directoryCount, databaseCount) = (job.directories.count, job.databases.count)
        Self.logger.notice("""
        Started a run with \(directoryCount, privacy: .public) directories and \(databaseCount, privacy: .public) databases
        """)

        var soFar = RunSoFar(jobID: jobID, startedAt: startedAt)
        do {
            try await perform(job, on: server, startedAt: startedAt) { step in
                if let next = soFar.take(step) { await report(next) }
            }
        } catch let stop as Stop {
            soFar.failure = stop.failure
        } catch is CancellationError {
            soFar.failure = .cancelled
        } catch {
            Self.logger.error("The run stopped on \(String(describing: type(of: error)), privacy: .public)")
            soFar.failure = .failed
        }

        let seconds = (ContinuousClock.now - clock).roundedSeconds
        if let failure = soFar.failure {
            Self.logger.error("The run failed after \(seconds, privacy: .public)s: \(failure.rawValue, privacy: .public)")
        } else {
            Self.logger.notice("The run completed its snapshot in \(seconds, privacy: .public)s")
        }
        return soFar.run(finishedAt: now())
    }

    private func perform(
        _ job: BackupJob,
        on server: Server,
        startedAt: Date,
        completed: (Step) async -> Void
    ) async throws {
        let drive = try locateDrive()
        let origin = try origin(for: server)

        await completed(.started(.checkingDirectories))
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
        await completed(.snapshotReady(pickedUp: partial.isPickedUp))
        let previous = try previousSnapshot(of: job, on: drive, folder: partial.jobFolder)

        var contents = SnapshotContents()
        try onDrive {
            try partial.removeDatabasesFolder()
            try partial.write(manifest(job, server: server, partial: partial, contents: contents, completedAt: nil))
        }

        let pull = DirectoryPull(rsync: rsync)
        for (directory, destination) in zip(job.directories, partial.destinations) {
            let parts = ["files"] + directory.folder.split(separator: "/").map(String.init)
            let linkTo = previous.flatMap { RealFolder.existing(parts, under: $0) }
            await completed(.started(.pulling(folder: directory.folder)))
            let report = try await pull.pull(directory, from: origin, into: destination, linkingTo: linkTo)
            await completed(.pulled(report))
            if let failure = report.failure { throw Stop(failure: failure) }
            contents.directories.append(
                SnapshotManifest.Directory(path: directory.path, folder: directory.folder, vanishedFiles: report.vanishedFiles)
            )
            try onDrive { try partial.write(manifest(job, server: server, partial: partial, contents: contents, completedAt: nil)) }
        }

        try await dumpDatabases(of: job, from: origin, into: partial, completed: completed) { database in
            contents.databases.append(database)
            try onDrive { try partial.write(manifest(job, server: server, partial: partial, contents: contents, completedAt: nil)) }
        }

        await completed(.started(.completing))
        let completedAt = now()
        try onDrive {
            try partial.write(manifest(job, server: server, partial: partial, contents: contents, completedAt: completedAt))
            let name = try partial.complete(at: completedAt)
            try catalog.markComplete(partial.record.id, folder: name, at: completedAt)
        }
    }

    /// After the directories, into `databases/`. `stored` gets each dump that worked.
    private func dumpDatabases(
        of job: BackupJob,
        from origin: BackupOrigin,
        into partial: PartialSnapshot,
        completed: (Step) async -> Void,
        stored: (SnapshotManifest.Database) throws -> Void
    ) async throws {
        guard !job.databases.isEmpty else { return }
        let folder = try onDrive { try RealFolder.make([SnapshotManifest.databasesFolder], under: partial.url) }
        let dump = DatabaseDump(runner: dumps)
        for database in job.databases {
            await completed(.started(.dumping(database: database.settings.name)))
            let password = try passwords.password(forDatabase: database.id)
            let report = try await dump.dump(database, password: password, from: origin, into: folder)
            await completed(.dumped(report))
            if let failure = report.failure { throw Stop(failure: failure) }
            let settings = database.settings
            try stored(SnapshotManifest.Database(name: settings.name, kind: settings.kind, file: DumpCommand.fileName(for: settings)))
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

    private func origin(for server: Server) throws -> BackupOrigin {
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
        contents: SnapshotContents,
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
            directories: contents.directories,
            databases: contents.databases
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
