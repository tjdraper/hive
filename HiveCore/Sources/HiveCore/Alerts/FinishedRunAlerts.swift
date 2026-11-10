import Foundation
import GRDB
import HiveKit

/// What each finished run means for alerts. Runs are read from the job log rather than heard about as
/// they end, so a restart in between can't lose one.
struct FinishedRunAlerts: Sendable {
    let database: HiveDatabase
    let servers: ServerStore
    let scanner: any HostKeyScanning
    let fullDiskAccess: @Sendable () -> FullDiskAccess

    /// Runs after `logEntryID`, oldest first, stopping at the one going now.
    func finishedRuns(after logEntryID: Int64) throws -> [JobLogRecord] {
        let runs = try database.writer.read { database in
            try JobLogRecord
                .filter(Column("id") > logEntryID && JobLogRecord.kindColumn != RemovalLogRecord.kind)
                .order(Column("id"))
                .fetchAll(database)
        }
        return Array(runs.prefix { $0.finishedAt != nil })
    }

    /// `open` is the key of every alert open now.
    func changes(for run: JobLogRecord, open: Set<String>) async throws -> [AlertStore.Change] {
        guard let id = run.id else { return [] }
        let (jobID, serverID) = (run.jobID, run.serverID)
        guard let failure = run.failure else {
            var changes: [AlertStore.Change] = [
                .resolve(.backupFailing(jobID: jobID), notice: .backingUpAgain(jobID: jobID, logEntryID: id)),
                .resolve(.hostKeyChanged(serverID: serverID), notice: nil),
            ]
            if let previous = try previousCompleteRun(before: run) {
                let parts = SnapshotShrinkCheck.shrunkParts(of: run.run, comparedWith: previous.run)
                if !parts.isEmpty { changes.append(.open(.snapshotShrank(jobID: jobID, logEntryID: id, parts: parts))) }
            }
            return changes
        }

        // One alert for the whole Hive, not one for each job (§13).
        if let problem = driveProblem(failure) { return [.open(.driveUnavailable(problem))] }
        switch failure {
        // A run cut short by a restart runs again, and one cancelled was stopped on purpose.
        case .cancelled, .interrupted:
            return []
        case .hostKeyChanged:
            guard !open.contains(AlertCondition.hostKeyChanged(serverID: serverID).key),
                  let server = try servers.server(id: serverID)
            else { return [] }
            let offered = try await offeredKey(by: server)
            return [.open(.hostKeyChanged(serverID: serverID, confirmed: server.confirmedHostKey, offered: offered))]
        default:
            var changes: [AlertStore.Change] = [.open(.backupFailing(jobID: jobID))]
            if Self.cameAfterHostKeyCheck(failure) { changes.append(.resolve(.hostKeyChanged(serverID: serverID), notice: nil)) }
            return changes
        }
    }

    private func driveProblem(_ failure: BackupFailure) -> DriveProblem? {
        switch failure {
        case .driveNotChosen: .notChosen
        case .driveMissing: .missing
        case .driveNotThisHives: .notThisHives
        case .couldNotWriteSnapshot where fullDiskAccess() == .missing: .noFullDiskAccess
        default: nil
        }
    }

    /// Scanned the way Beekeeper scans before confirming, so the email shows the fingerprint Beekeeper will.
    private func offeredKey(by server: Server) async throws -> HostKeyFingerprint? {
        guard case .found(let key) = try await scanner.scan(server.connection) else { return nil }
        return key.hostKeyFingerprint
    }

    private func previousCompleteRun(before run: JobLogRecord) throws -> JobLogRecord? {
        guard let id = run.id else { return nil }
        return try database.writer.read { database in
            try JobLogRecord
                .filter(Column("jobID") == run.jobID && Column("id") < id && JobLogRecord.kindColumn != RemovalLogRecord.kind)
                .filter(Column("finishedAt") != nil && Column("failure") == nil)
                .order(Column("id").desc)
                .fetchOne(database)
        }
    }

    /// Failures that only come after `ssh` accepted the server's host key, which shows the confirmed key is back.
    private static func cameAfterHostKeyCheck(_ failure: BackupFailure) -> Bool {
        switch failure {
        case .loginRefused, .sourceMissing, .sourceEmpty, .sourceUnreadable, .someFilesNotTransferred, .dockerUnavailable,
             .databaseContainerNotFound, .databaseContainerNotUnique, .databaseDumpToolMissing, .databaseUnreachable,
             .databaseLoginRefused, .databaseMissing, .databaseNotPermitted, .databaseDumpEmpty, .databaseDumpIncomplete,
             .databaseDumpFailed:
            true
        default:
            false
        }
    }
}
