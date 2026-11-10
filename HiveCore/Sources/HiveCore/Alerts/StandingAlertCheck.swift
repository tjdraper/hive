import Foundation
import HiveKit

/// Conditions that hold whether or not anything runs: overdue jobs, quotas and the drive's space. Also
/// ends conditions a run opened, once what caused them is fixed.
struct StandingAlertCheck: Sendable {
    /// Free space below this share of the drive is filling up.
    static let fillingUpBelow = 0.10
    /// Higher than `fillingUpBelow`, so a drive hovering at the line doesn't send an email each time it crosses.
    static let roomyAbove = 0.15

    let database: HiveDatabase
    let drives: BackupDriveLocator
    let statuses: JobStatusReader
    let fullDiskAccess: @Sendable () -> FullDiskAccess

    func changes(open: [AlertRecord]) async throws -> [AlertStore.Change] {
        let servers = try ServerStore(database: database).all()
        let drive = try drives.locate()
        let opened = open.map(\.facts)
        let ended = try opened.flatMap { try ended($0, servers: servers, drive: drive) }
        let overdue = try await overdueJobs(opened: opened)
        return try ended + overdue + overQuota(opened: opened) + driveSpace(drive, servers: servers)
    }

    /// Conditions opened by runs that no longer hold, or whose job or server was removed.
    private func ended(_ facts: AlertFacts, servers: [Server], drive: DriveLookup) throws -> [AlertStore.Change] {
        switch facts {
        case .driveUnavailable(.noFullDiskAccess):
            guard fullDiskAccess() != .missing else { return [] }
            return [.resolve(.driveUnavailable, notice: nil)]
        case .driveUnavailable:
            guard case .ready = drive else { return [] }
            return [.resolve(.driveUnavailable, notice: nil)]
        case .hostKeyChanged(let serverID, let confirmed, _):
            let server = servers.first { $0.id == serverID }
            // A device confirmed the new key, or the server was removed.
            guard server == nil || server?.confirmedHostKey != confirmed else { return [] }
            return [.resolve(.hostKeyChanged(serverID: serverID), notice: nil)]
        case .backupFailing(let jobID):
            guard try BackupJobStore(database: database).job(id: jobID) == nil else { return [] }
            return [.resolve(.backupFailing(jobID: jobID), notice: nil)]
        default:
            return []
        }
    }

    /// A job whose last run failed isn't also emailed about as overdue, since its failure already is.
    /// Nor is one waiting or running, such as each job due while Hive was off.
    private func overdueJobs(opened: [AlertFacts]) async throws -> [AlertStore.Change] {
        let statuses = try await statuses.statuses()
        let jobs = Set(statuses.map(\.jobID))
        var changes = opened.compactMap { facts -> AlertStore.Change? in
            guard case .jobOverdue(let jobID, _) = facts, !jobs.contains(jobID) else { return nil }
            return .resolve(.jobOverdue(jobID: jobID), notice: nil)
        }
        for status in statuses where status.state == .idle {
            if let since = status.overdueSince, !Self.isAlertedFailure(status.lastRun?.run.failure) {
                changes.append(.open(.jobOverdue(jobID: status.jobID, since: since)))
            } else {
                changes.append(.resolve(.jobOverdue(jobID: status.jobID), notice: nil))
            }
        }
        return changes
    }

    private func overQuota(opened: [AlertFacts]) throws -> [AlertStore.Change] {
        let over = try RetentionStore(database: database).overQuota()
        let ended = opened.compactMap { facts -> AlertStore.Change? in
            guard case .overQuota(let serverID, _) = facts, over[serverID] == nil else { return nil }
            return .resolve(.overQuota(serverID: serverID), notice: nil)
        }
        return ended + over.map { .open(.overQuota(serverID: $0.key, since: $0.value)) }
    }

    /// Only while the drive is there to measure.
    private func driveSpace(_ drive: DriveLookup, servers: [Server]) -> [AlertStore.Change] {
        guard case .ready(let located) = drive,
              let volume = drives.volumes.mountedVolumes().first(where: { $0.uuid == located.identity.volumeUUID }),
              volume.totalBytes > 0
        else { return [] }

        var changes: [AlertStore.Change] = []
        let free = Double(volume.availableBytes) / Double(volume.totalBytes)
        if free < Self.fillingUpBelow {
            changes.append(.open(.driveFillingUp))
        } else if free > Self.roomyAbove {
            changes.append(.resolve(.driveFillingUp, notice: nil))
        }
        let quotas = servers.compactMap(\.quotaBytes).reduce(0, +)
        changes.append(quotas > volume.totalBytes ? .open(.quotasExceedDrive) : .resolve(.quotasExceedDrive, notice: nil))
        return changes
    }

    private static func isAlertedFailure(_ failure: BackupFailure?) -> Bool {
        guard let failure else { return false }
        return failure != .cancelled && failure != .interrupted
    }
}
