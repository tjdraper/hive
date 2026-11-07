import Foundation
import HiveKit
import os

/// Queues each job when one of its times comes (§11). It checks the clock every half minute rather
/// than setting a timer for each time, so a Mac that slept through a time, or a Hive that was off,
/// runs the job once as soon as it's back, however many of its times passed.
actor BackupScheduler {
    static let checkInterval: Duration = .seconds(30)

    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Scheduling")

    private let jobs: BackupJobStore
    private let schedules: ScheduleStore
    private let schedule: ScheduleCalendar
    private let runs: BackupRunCoordinator
    private let jobLog: JobLog
    private let now: @Sendable () -> Date
    private var lastPrunedAt: Date?

    init(
        database: HiveDatabase,
        schedule: ScheduleCalendar,
        runs: BackupRunCoordinator,
        now: @escaping @Sendable () -> Date
    ) {
        jobs = BackupJobStore(database: database)
        schedules = ScheduleStore(database: database)
        jobLog = JobLog(database: database)
        self.schedule = schedule
        self.runs = runs
        self.now = now
    }

    /// Until the task running it is cancelled.
    func run() async {
        while !Task.isCancelled {
            await check()
            try? await Task.sleep(for: Self.checkInterval)
        }
    }

    /// Queues every job whose next time has come, and works out its next. A new job, or one whose
    /// times changed, gets its next time without running now.
    func check() async {
        let now = now()
        do {
            let stored = try schedules.all()
            var queued = 0
            for job in try jobs.all() {
                let key = schedule.key(for: job.times)
                if let record = stored[job.id], record.scheduleKey == key {
                    guard record.nextRunAt <= now else { continue }
                    // Queued before the next time is saved, so a crash in between can't lose the run.
                    if try await runs.queueScheduled(jobID: job.id) == .queued { queued += 1 }
                }
                guard let next = schedule.nextRun(after: now, times: job.times) else { continue }
                try schedules.save(JobScheduleRecord(jobID: job.id, scheduleKey: key, nextRunAt: next))
            }
            if queued > 0 { Self.logger.notice("Queued \(queued, privacy: .public) scheduled runs") }
            try pruneJobLog(now: now)
        } catch {
            Self.logger.error("Couldn't check the schedules: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Once a day, and on the first check after starting.
    private func pruneJobLog(now: Date) throws {
        if let lastPrunedAt, now.timeIntervalSince(lastPrunedAt) < 24 * 60 * 60 { return }
        guard let yearAgo = schedule.calendar.date(byAdding: .year, value: -1, to: now) else { return }
        let removed = try jobLog.removeEntries(startedBefore: yearAgo)
        lastPrunedAt = now
        if removed > 0 { Self.logger.notice("Removed \(removed, privacy: .public) job log entries older than a year") }
    }
}
