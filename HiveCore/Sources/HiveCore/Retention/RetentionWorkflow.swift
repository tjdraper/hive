import Foundation
import HiveKit
import os

/// One retention pass over the backup drive (§10): finish any removal cut short, count what changed,
/// remove what each job's tiers no longer keep and the partial snapshots newer ones replaced, then bring
/// each server within its quota by removing its oldest daily snapshots. Snapshots of removed jobs and
/// servers stay until a device deletes them.
///
/// It runs on the job queue, between runs, so nothing it touches is being written. After a restore it
/// counts but removes nothing until a device starts it again (F3).
struct RetentionWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Retention")

    /// What one job's part of the pass did, for its job log entry.
    private struct JobOutcome {
        var removed: [RemovedSnapshot] = []
        var notRemoved: [UnremovedSnapshot] = []
    }

    let drives: BackupDriveLocator
    let store: RetentionStore
    let space: SnapshotSpaceStore
    let removals: SnapshotRemovalStore
    let jobLog: JobLog
    let calendar: Calendar
    let now: @Sendable () -> Date

    init(
        drives: BackupDriveLocator,
        store: RetentionStore,
        space: SnapshotSpaceStore,
        removals: SnapshotRemovalStore,
        jobLog: JobLog,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date
    ) {
        self.drives = drives
        self.store = store
        self.space = space
        self.removals = removals
        self.jobLog = jobLog
        self.calendar = calendar
        self.now = now
    }

    init(database: HiveDatabase, drives: BackupDriveLocator, calendar: Calendar, now: @escaping @Sendable () -> Date) {
        self.init(
            drives: drives,
            store: RetentionStore(database: database),
            space: SnapshotSpaceStore(database: database),
            removals: SnapshotRemovalStore(database: database),
            jobLog: JobLog(database: database),
            calendar: calendar,
            now: now
        )
    }

    var remover: SnapshotRemover {
        SnapshotRemover(removals: removals, space: space)
    }

    private var counter: SnapshotSpaceCounter {
        SnapshotSpaceCounter(space: space, store: store)
    }

    /// After a run of the job: its server's jobs and quota. Returns what it logged.
    @discardableResult
    @concurrent func pass(afterRunOf jobID: UUID) async -> [RemovalLogEntry] {
        guard let serverID = try? store.serverID(ofJob: jobID) else { return [] }
        return await pass(servers: [serverID])
    }

    /// Every server, or only those in `servers`. Stops between steps once the task is cancelled, leaving
    /// a removal cut short for the next pass to finish. Returns what it logged.
    @discardableResult
    @concurrent func pass(servers: Set<UUID>? = nil) async -> [RemovalLogEntry] {
        let clock = ContinuousClock.now
        guard case .ready(let drive) = (try? drives.locate()) ?? .unavailable(.failed) else {
            Self.logger.notice("Skipped retention: the backup drive isn't available")
            return []
        }
        var outcomes: [UUID: JobOutcome] = [:]
        var logged: [RemovalLogEntry] = []
        do {
            let hiveFolder = try DriveFolder(at: drive.hiveFolder)
            let driveUUID = drive.identity.volumeUUID.uuidString
            let paused = try store.isPaused()
            if paused {
                Self.logger.notice("Retention is paused after a restore: counting only")
            } else {
                logged += try RemovalRecovery(store: store, removals: removals, remover: remover, jobLog: jobLog, now: now)
                    .finish(onDrive: driveUUID, in: hiveFolder)
            }
            for server in try store.servers(servers) {
                try Task.checkCancellation()
                try pass(over: server, driveUUID: driveUUID, in: hiveFolder, paused: paused, outcomes: &outcomes)
            }
        } catch is CancellationError {
            Self.logger.notice("Retention stopped part way, as Hive stops")
        } catch {
            Self.logger.error("Retention stopped on \(Self.described(error), privacy: .public)")
        }

        let removed = outcomes.values.flatMap(\.removed)
        for (jobID, outcome) in outcomes {
            do {
                let entry = try jobLog.recordRemovals(ofJob: jobID, removed: outcome.removed, notRemoved: outcome.notRemoved, at: now())
                logged += entry.map { [$0] } ?? []
            } catch {
                Self.logger.error("Couldn't record removals in the job log: \(Self.described(error), privacy: .public)")
            }
        }
        let freedBytes = removed.reduce(0) { $0 + $1.bytesFreed }
        let seconds = (ContinuousClock.now - clock).roundedSeconds
        Self.logger.notice("""
        Retention removed \(removed.count, privacy: .public) snapshots, freeing \(freedBytes, privacy: .public) bytes, \
        in \(seconds, privacy: .public)s
        """)
        return logged
    }

    /// A job whose folder is open on the drive, and which no run is writing to.
    private struct OpenJob {
        let job: RetentionStore.Job
        let folders: SnapshotFolders
        let folder: DriveFolder
    }

    /// Adds what it removes from each job to `outcomes` as it goes, so a pass cut short still records it.
    private func pass(
        over server: RetentionStore.Server,
        driveUUID: String,
        in hiveFolder: DriveFolder,
        paused: Bool,
        outcomes: inout [UUID: JobOutcome]
    ) throws {
        var openJobs: [OpenJob] = []
        var anyRunning = false
        for job in server.jobs {
            try Task.checkCancellation()
            guard let folders = job.folders else { continue }
            guard try !removals.isRunning(jobID: job.id) else {
                anyRunning = true
                continue
            }
            guard let folder = Self.openJobFolder(folders, in: hiveFolder) else { continue }
            let open = OpenJob(job: job, folders: folders, folder: folder)
            try count(open, driveUUID: driveUUID)
            openJobs.append(open)
        }
        guard !paused else { return }

        var quotaCandidates: [(SnapshotRecord, OpenJob)] = []
        for open in openJobs {
            let snapshots = try counter.ownSnapshots(jobID: open.job.id, driveUUID: driveUUID, folders: open.folders)
            let decision = TierResolver(calendar: calendar).decide(snapshots, tiers: open.job.tiers)
            for removal in decision.removals {
                try Task.checkCancellation()
                try remove(removal.snapshot, because: removal.reason, from: open, driveUUID: driveUUID, into: &outcomes)
            }
            quotaCandidates += decision.dailyOnly.map { ($0, open) }
        }

        if anyRunning {
            Self.logger.notice("Skipped a server's quota while one of its jobs runs")
        } else {
            try applyQuota(of: server, to: openJobs, removing: quotaCandidates, driveUUID: driveUUID, outcomes: &outcomes)
        }
        // What each snapshot frees, for the ones next to those removed.
        for open in openJobs { try count(open, driveUUID: driveUUID) }
    }

    /// Removes the oldest daily snapshots across the server's jobs until it fits its quota, or none are
    /// left, and marks whether it's over.
    private func applyQuota(
        of server: RetentionStore.Server,
        to openJobs: [OpenJob],
        removing candidates: [(SnapshotRecord, OpenJob)],
        driveUUID: String,
        outcomes: inout [UUID: JobOutcome]
    ) throws {
        guard let quota = server.quotaBytes else {
            try store.clearOverQuota(serverID: server.id)
            return
        }
        let jobsUsed = try openJobs.map { try space.usedBytes(ofJob: $0.job.id, onDrive: driveUUID) }
        guard !jobsUsed.contains(nil) else {
            Self.logger.notice("Skipped a server's quota: a job's space isn't counted")
            return
        }
        var used = jobsUsed.reduce(0) { $0 + ($1 ?? 0) }
        for (snapshot, open) in candidates.sorted(by: { $0.0.date < $1.0.date }) where used > quota {
            try Task.checkCancellation()
            used -= try remove(snapshot, because: .quota, from: open, driveUUID: driveUUID, into: &outcomes) ?? 0
        }
        if used > quota {
            Self.logger.notice("A server is over its quota with only monthly and newest snapshots left")
            try store.markOverQuota(serverID: server.id, at: now())
        } else {
            try store.clearOverQuota(serverID: server.id)
        }
    }

    /// A job that can't be counted is left uncounted, and its server's quota waits for it.
    private func count(_ open: OpenJob, driveUUID: String) throws {
        do {
            try counter.update(jobID: open.job.id, driveUUID: driveUUID, folders: open.folders, in: open.folder)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("Couldn't count a job's snapshots: \(Self.described(error), privacy: .public)")
        }
    }

    /// What it freed, when it was removed. Throws only when the task is cancelled, which leaves a removal
    /// under way for the next pass to finish.
    @discardableResult
    private func remove(
        _ snapshot: SnapshotRecord,
        because reason: RemovalReason,
        from open: OpenJob,
        driveUUID: String,
        into outcomes: inout [UUID: JobOutcome]
    ) throws -> Int64? {
        let problem: RemovalProblem
        do {
            switch try remover.remove(snapshot, because: reason, in: open.folder, folders: open.folders, driveUUID: driveUUID) {
            case .removed(let bytesFreed):
                outcomes[open.job.id, default: JobOutcome()].removed.append(RemovedSnapshot(
                    snapshotID: snapshot.id,
                    date: snapshot.date,
                    wasComplete: snapshot.state == .complete,
                    reason: reason,
                    bytesFreed: bytesFreed
                ))
                return bytesFreed
            case .missing:
                Self.logger.notice("A snapshot to remove had already gone from the drive")
                return nil
            case .refused(let refusal):
                problem = refusal
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("Couldn't remove a snapshot: \(Self.described(error), privacy: .public)")
            problem = .couldNotRemove
        }
        Self.logger.error("Didn't remove a snapshot: \(problem.rawValue, privacy: .public)")
        outcomes[open.job.id, default: JobOutcome()].notRemoved.append(UnremovedSnapshot(
            snapshotID: snapshot.id,
            date: snapshot.date,
            wasComplete: snapshot.state == .complete,
            reason: reason,
            problem: problem
        ))
        return nil
    }

    /// Nil when it isn't on the drive, or isn't a real folder there.
    static func openJobFolder(_ folders: SnapshotFolders, in hiveFolder: DriveFolder) -> DriveFolder? {
        do {
            guard try hiveFolder.contains(folders.server) else { return nil }
            let serverFolder = try DriveFolder(name: folders.server, in: hiveFolder)
            guard try serverFolder.contains(folders.job) else { return nil }
            return try DriveFolder(name: folders.job, in: serverFolder)
        } catch {
            Self.logger.error("Couldn't open a job's folder on the drive: \(Self.described(error), privacy: .public)")
            return nil
        }
    }

    /// For the system log: a drive error's kind and code, and for anything else only its type, since a
    /// store error's description can hold values.
    static func described(_ error: any Error) -> String {
        if let error = error as? DriveFolderError { return String(describing: error) }
        return String(describing: type(of: error))
    }
}
