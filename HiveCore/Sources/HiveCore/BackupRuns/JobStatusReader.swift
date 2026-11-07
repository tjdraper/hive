import Foundation
import GRDB
import HiveKit

/// Puts together where each job stands, from the queue, the job log, the catalog and its schedule.
struct JobStatusReader: Sendable {
    let database: HiveDatabase
    let runs: BackupRunCoordinator
    let schedule: ScheduleCalendar
    let now: @Sendable () -> Date

    /// Every job's, or only `jobID`'s.
    func statuses(ofJob jobID: UUID? = nil) async throws -> [JobStatus] {
        let current = await runs.current()
        let now = now()
        let jobLog = JobLog(database: database)
        let queued = try Dictionary(uniqueKeysWithValues: BackupQueue(database: database).all().map { ($0.jobID, $0) })
        let schedules = try ScheduleStore(database: database).all()
        let (createdAt, lastSnapshots) = try await database.writer.read { database in
            let created = try Dictionary(uniqueKeysWithValues: BackupJobRecord.fetchAll(database).map { ($0.id, $0.createdAt) })
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT jobID, MAX(completedAt) AS completedAt FROM snapshot WHERE state = ? GROUP BY jobID",
                arguments: [SnapshotState.complete.rawValue]
            )
            let snapshots: [UUID: Date] = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                (row["completedAt"] as Date?).map { (row["jobID"] as UUID, $0) }
            })
            return (created, snapshots)
        }

        let jobs = try BackupJobStore(database: database).all().filter { jobID == nil || $0.id == jobID }
        return try jobs.map { job in
            let running = current?.entry.run.jobID == job.id
            let state: JobRunState = running ? .running : queued[job.id] == nil ? .idle : .waiting
            let lastSnapshotAt = lastSnapshots[job.id]
            return JobStatus(
                jobID: job.id,
                state: state,
                current: running ? current?.entry : nil,
                step: running ? current?.step : nil,
                lastRun: try jobLog.lastFinished(ofJob: job.id),
                lastSnapshotAt: lastSnapshotAt,
                nextRunAt: schedules[job.id]?.nextRunAt ?? schedule.nextRun(after: now, times: job.times),
                overdueSince: OverdueCheck(schedule: schedule).overdueSince(
                    lastSnapshotAt ?? createdAt[job.id] ?? now,
                    times: job.times,
                    isRunning: running,
                    now: now
                )
            )
        }
    }
}
