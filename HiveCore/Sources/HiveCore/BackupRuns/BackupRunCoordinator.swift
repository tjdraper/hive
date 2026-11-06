import Foundation
import GRDB
import HiveKit

/// Starts runs from Run Now, one at a time, and keeps each job's latest run in memory. C5 replaces it
/// with the queue and the job log.
actor BackupRunCoordinator {
    enum Start: Equatable {
        case started(BackupRun)
        case busy
        case unknownJob
    }

    private let workflow: BackupRunWorkflow
    private var current: Task<Void, Never>?
    private var latest: [UUID: BackupRun] = [:]

    init(workflow: BackupRunWorkflow) {
        self.workflow = workflow
    }

    func start(jobID: UUID, by deviceID: UUID) throws -> Start {
        guard current == nil else { return .busy }
        guard try recordStart(of: jobID, by: deviceID) else { return .unknownJob }

        let run = BackupRun(jobID: jobID, startedAt: workflow.now(), finishedAt: nil, failure: nil, directories: [])
        latest[jobID] = run
        current = Task { [workflow] in
            let finished: BackupRun
            do {
                finished = try await workflow.run(jobID: jobID) { await self.update($0) }
                    ?? BackupRun(jobID: jobID, startedAt: run.startedAt, finishedAt: workflow.now(), failure: .failed, directories: [])
            } catch {
                finished = BackupRun(jobID: jobID, startedAt: run.startedAt, finishedAt: workflow.now(), failure: .failed, directories: [])
            }
            self.finish(finished)
        }
        return .started(run)
    }

    func latestRun(ofJob jobID: UUID) -> BackupRun? {
        latest[jobID]
    }

    /// Returns once the run going now, if any, has finished.
    func waitUntilIdle() async {
        await current?.value
    }

    private func update(_ run: BackupRun) {
        latest[run.jobID] = run
    }

    private func finish(_ run: BackupRun) {
        latest[run.jobID] = run
        current = nil
    }

    /// Returns false when no job has that ID.
    private func recordStart(of jobID: UUID, by deviceID: UUID) throws -> Bool {
        try workflow.database.writer.write { database in
            guard let row = try Row.fetchOne(
                database,
                sql: """
                SELECT backupJob.name AS jobName, server.name AS serverName
                FROM backupJob JOIN server ON server.id = backupJob.serverID
                WHERE backupJob.id = ?
                """,
                arguments: [jobID]
            ) else { return false }
            let event = AuditEvent.backupRunStarted(jobID: jobID, serverName: row["serverName"], jobName: row["jobName"])
            try AuditLog.record(event, by: deviceID, at: workflow.now(), in: database)
            return true
        }
    }
}
