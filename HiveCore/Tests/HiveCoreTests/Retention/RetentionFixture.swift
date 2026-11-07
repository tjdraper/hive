import Darwin
import Foundation
import GRDB
@testable import HiveCore
import HiveKit
import Hummingbird

/// Retention helpers on a backup run fixture, whose runs pull with the bundled rsync between temporary
/// folders.
extension BackupRunFixture {
    /// Runs `job` once for each gap, moving the clock on by that many days first. Each run adds a file
    /// of its own, so each snapshot frees something when it's removed.
    @discardableResult
    func runDaysApart(_ gaps: [Int], job: BackupJob? = nil, source: String = "srv/site") async throws -> [SnapshotRecord] {
        let job = job ?? self.job
        for gap in gaps {
            clock.advance(by: TimeInterval(gap) * 24 * 60 * 60)
            try write(String(repeating: "x", count: 20_000) + "\(clock.now)", to: "\(source)/run-\(UUID().uuidString).txt")
            let started = try await runNow(job)
            guard started.status == .accepted else { throw APIFixtureError.unexpectedStatus(started.status) }
            await runs.waitUntilIdle()
        }
        return try completeSnapshots(of: job)
    }

    /// Oldest first.
    func completeSnapshots(of job: BackupJob? = nil) throws -> [SnapshotRecord] {
        try catalog().filter { $0.jobID == (job ?? self.job).id && $0.state == .complete }.sorted { $0.date < $1.date }
    }

    /// A workflow of its own, to run a pass outside the queue.
    func retentionWorkflow() -> RetentionWorkflow {
        RetentionWorkflow(
            drives: BackupDriveLocator(store: BackupDriveStore(database: database), volumes: api.volumes, hiveID: api.signIn.hiveID),
            store: RetentionStore(database: database),
            space: SnapshotSpaceStore(database: database),
            removals: SnapshotRemovalStore(database: database),
            jobLog: JobLog(database: database),
            calendar: APIFixture.calendar,
            now: { [clock] in clock.now }
        )
    }

    func retentionPass() async {
        await runs.requestRetentionPass()
        await runs.waitUntilIdle()
    }

    func setQuota(_ bytes: Int64?) async throws {
        var draft = serverRecord.draft
        draft.quotaBytes = bytes
        let answer = try await api.send(.put, HiveEndpoint.server(serverRecord.id), json: draft)
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
    }

    func setTiers(daily: Int, monthly: Int, of job: BackupJob? = nil) async throws {
        let job = job ?? self.job
        var draft = job.draft
        draft.retention = RetentionTiers(dailySnapshots: daily, monthlySnapshots: monthly)
        let answer = try await api.send(.put, HiveEndpoint.job(job.id), json: draft)
        guard answer.status == .ok else { throw APIFixtureError.unexpectedStatus(answer.status) }
    }

    var database: HiveDatabase {
        api.signIn.database
    }

    func usedBytes(of job: BackupJob? = nil) throws -> Int64? {
        try SnapshotSpaceStore(database: database).usedBytes(ofJob: (job ?? self.job).id, onDrive: Self.volumeUUID.uuidString)
    }

    func jobFolder(of job: BackupJob? = nil) throws -> URL {
        guard let record = try catalog().first(where: { $0.jobID == (job ?? self.job).id }) else { throw RetentionFixtureError.noSnapshots }
        return hiveFolder.appending(path: "\(record.serverFolder)/\(record.jobFolder)", directoryHint: .isDirectory)
    }

    /// Every inode in the job's snapshots on the drive, counted the long way.
    func snapshotBlocks(of job: BackupJob? = nil) throws -> [UInt64: Int64] {
        try catalog()
            .filter { $0.jobID == (job ?? self.job).id }
            .reduce(into: [:]) { found, record in found.merge(DriveUsage.blocks(under: snapshotURL(record))) { first, _ in first } }
    }

    func overQuota() throws -> [UUID: Date] {
        try RetentionStore(database: database).overQuota()
    }

    func removals() async throws -> [RemovalLogEntry] {
        try await jobLog().entries.compactMap { entry in
            guard case .removal(let removal) = entry else { return nil }
            return removal
        }
    }
}

/// The space a folder takes, counted the long way: every file's inode once, and every folder.
enum DriveUsage {
    static func bytes(under folder: URL) -> Int64 {
        blocks(under: folder).values.reduce(0, +)
    }

    /// Each inode under `folder`, folders included, with the space it takes, never following a link.
    static func blocks(under folder: URL) -> [UInt64: Int64] {
        var found: [UInt64: Int64] = [:]
        var info = stat()
        guard lstat(folder.fileSystemPath, &info) == 0 else { return found }
        found[UInt64(info.st_ino)] = Int64(info.st_blocks) * 512
        for path in FileManager.default.subpaths(atPath: folder.fileSystemPath) ?? [] {
            guard lstat(folder.appending(path: path).fileSystemPath, &info) == 0 else { continue }
            found[UInt64(info.st_ino)] = Int64(info.st_blocks) * 512
        }
        return found
    }

    /// What went from `before` to `after`.
    static func freed(from before: [UInt64: Int64], to after: [UInt64: Int64]) -> Int64 {
        before.filter { after[$0.key] == nil }.values.reduce(0, +)
    }
}

enum RetentionFixtureError: Error {
    case noSnapshots
}
