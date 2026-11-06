import Foundation
import HiveKit
import os

/// Adding, changing and removing backup jobs. Passwords are sealed before anything is stored.
struct BackupJobWorkflow: Sendable {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Configuration")

    let store: BackupJobStore
    let sealer: SecretSealer
    let now: @Sendable () -> Date

    /// Returns nil when no server has that ID.
    func add(_ draft: BackupJobDraft, toServer serverID: UUID, by deviceID: UUID) throws -> BackupJob? {
        let sealed = try SealedJobDraft(BackupJobDraftCheck.validated(draft), sealer: sealer)
        guard let job = try store.add(sealed, toServer: serverID, by: deviceID, at: now()) else { return nil }
        Self.logger.notice(
            "Added a job with \(job.directories.count, privacy: .public) directories and \(job.databases.count, privacy: .public) databases"
        )
        return job
    }

    /// Returns nil when no job has that ID.
    func change(id: UUID, to draft: BackupJobDraft, by deviceID: UUID) throws -> BackupJob? {
        let sealed = try SealedJobDraft(BackupJobDraftCheck.validated(draft), sealer: sealer)
        guard let (old, new) = try store.change(id: id, to: sealed, by: deviceID, at: now()) else { return nil }
        let changed = BackupJobStore.changes(from: old, to: new, passwordsEnteredAt: sealed.passwordPositions)
        if !changed.isEmpty {
            let reasons = ConfirmationRequirement.logged(
                ConfirmationRequirement.reasons(from: old, to: new, passwordsEnteredAt: sealed.passwordPositions)
            )
            Self.logger.notice("Changed a job (\(changed.count, privacy: .public) changes, to confirm: \(reasons, privacy: .public))")
        }
        return new
    }

    func remove(id: UUID, by deviceID: UUID) throws -> Bool {
        guard try store.remove(id: id, by: deviceID, at: now()) != nil else { return false }
        Self.logger.notice("Removed a job from the configuration")
        return true
    }
}
