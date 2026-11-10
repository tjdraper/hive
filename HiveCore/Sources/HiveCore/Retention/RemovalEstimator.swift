import Foundation
import GRDB
import HiveKit

/// How many snapshots a lower quota or lower tiers would remove that the saved ones don't, worked out
/// from the catalog the way a retention pass decides (§10), without touching the drive. Snapshots
/// waiting to be deleted by hand are left out, as already going.
struct RemovalEstimator: Sendable {
    let database: HiveDatabase
    let calendar: Calendar

    private var store: RetentionStore {
        RetentionStore(database: database)
    }

    /// Nil when no job has that ID.
    func estimate(tiers: RetentionTiers, ofJob jobID: UUID) throws -> RemovalEstimate? {
        guard let job = try store.servers().flatMap(\.jobs).first(where: { $0.id == jobID }) else { return nil }
        guard let driveUUID = try chosenDriveUUID() else { return RemovalEstimate(snapshotCount: 0) }
        let snapshots = try snapshots(of: job, onDrive: driveUUID)
        let resolver = TierResolver(calendar: calendar)
        let removedNow = Set(resolver.decide(snapshots, tiers: job.tiers).removals.map(\.snapshot.id))
        let removedThen = resolver.decide(snapshots, tiers: tiers).removals.map(\.snapshot.id)
        return RemovalEstimate(snapshotCount: removedThen.count { !removedNow.contains($0) })
    }

    /// Nil when no server has that ID. Removing one snapshot can leave its neighbors freeing more, so a
    /// quota may remove fewer than this, never more.
    func estimate(quotaBytes: Int64?, ofServer serverID: UUID) throws -> RemovalEstimate? {
        guard let server = try store.servers([serverID]).first else { return nil }
        guard let driveUUID = try chosenDriveUUID() else { return RemovalEstimate(snapshotCount: 0) }

        let resolver = TierResolver(calendar: calendar)
        var usedBytes: Int64 = 0
        var candidates: [SnapshotRecord] = []
        for job in server.jobs {
            let snapshots = try snapshots(of: job, onDrive: driveUUID)
            guard !snapshots.isEmpty else { continue }
            guard let used = try SnapshotSpaceStore(database: database).usedBytes(ofJob: job.id, onDrive: driveUUID) else {
                return RemovalEstimate(snapshotCount: nil)
            }
            let decision = resolver.decide(snapshots, tiers: job.tiers)
            // The pass removes what the tiers don't keep before it looks at the quota. What a snapshot
            // frees isn't known for a moment after a change nearby, and counting it as nothing errs toward more.
            usedBytes += used - decision.removals.reduce(0) { $0 + ($1.snapshot.freesBytes ?? 0) }
            candidates += decision.dailyOnly
        }
        candidates.sort { $0.date < $1.date }
        let removedNow = Self.quotaRemovals(quotaBytes: server.quotaBytes, usedBytes: usedBytes, candidates: candidates)
        let removedThen = Self.quotaRemovals(quotaBytes: quotaBytes, usedBytes: usedBytes, candidates: candidates)
        return RemovalEstimate(snapshotCount: max(0, removedThen - removedNow))
    }

    /// How many of `candidates`, oldest first, the quota removes.
    private static func quotaRemovals(quotaBytes: Int64?, usedBytes: Int64, candidates: [SnapshotRecord]) -> Int {
        guard let quotaBytes else { return 0 }
        var used = usedBytes
        var removed = 0
        for candidate in candidates where used > quotaBytes {
            used -= candidate.freesBytes ?? 0
            removed += 1
        }
        return removed
    }

    private func chosenDriveUUID() throws -> String? {
        try database.writer.read { try BackupDriveStore.chosen(in: $0)?.volumeUUID.uuidString }
    }

    /// The job's own snapshots, as a pass sees them, less those waiting to be deleted.
    private func snapshots(of job: RetentionStore.Job, onDrive driveUUID: String) throws -> [SnapshotRecord] {
        guard let folders = job.folders else { return [] }
        let deleting = try database.writer.read { database in
            try Set(UUID.fetchAll(database, sql: "SELECT snapshotID FROM snapshotDeletion"))
        }
        return try store.snapshots(ofJob: job.id, onDrive: driveUUID).filter {
            $0.serverFolder == folders.server && $0.jobFolder == folders.job && SnapshotFolderName.isSnapshot($0.folder)
                && !deleting.contains($0.id)
        }
    }
}
