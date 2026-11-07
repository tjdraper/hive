import Foundation
import HiveKit
import os

/// Runs the queue (§11): one job at a time, keeping the Mac awake meanwhile, recording each run in the
/// job log as it goes and telling listeners about it. Retention runs on the queue too, after each run and
/// once a day, so it never touches a snapshot being written (§10).
actor BackupRunCoordinator {
    private static let logger = Logger(subsystem: HiveLog.subsystem, category: "Backup")

    /// The run going now.
    private struct Live {
        var entry: JobLogRecord
        var step: RunStep?
        var task: Task<BackupRun?, Never>?
    }

    nonisolated let events = RunEventBroadcaster()

    private let workflow: BackupRunWorkflow
    private let retention: RetentionWorkflow
    private let queue: BackupQueue
    private let sleep: any SleepPreventing
    private let driveWait: StartupDriveWait
    private var live: Live?
    private var draining: Task<Void, Never>?
    private var retentionPass: Task<Void, Never>?
    private var retentionWaiting = false
    private var stopping = false

    /// Runs within `startupDriveGrace` of now wait for the backup drive to mount, using `pause`.
    init(
        workflow: BackupRunWorkflow,
        retention: RetentionWorkflow,
        sleep: any SleepPreventing,
        startupDriveGrace: TimeInterval,
        pause: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.workflow = workflow
        self.retention = retention
        queue = BackupQueue(database: workflow.database)
        self.sleep = sleep
        driveWait = StartupDriveWait(
            drives: workflow.drives,
            grace: startupDriveGrace,
            hiveStartedAt: workflow.now(),
            pause: pause,
            now: workflow.now
        )
    }

    /// Once, when Hive starts, before anything else uses the queue: marks the runs a restart cut short
    /// as interrupted, then runs whatever is waiting.
    func start() throws {
        let interrupted = try queue.recoverInterruptedRuns(at: workflow.now())
        if interrupted > 0 { Self.logger.notice("Marked \(interrupted, privacy: .public) runs interrupted by a restart") }
        kick()
    }

    /// A pass over every server, once the runs waiting have gone.
    func requestRetentionPass() {
        retentionWaiting = true
        kick()
    }

    /// Recorded in the audit log.
    func runNow(jobID: UUID, by deviceID: UUID) throws -> BackupQueue.Addition {
        try add(jobID: jobID, trigger: .runNow, by: deviceID)
    }

    func queueScheduled(jobID: UUID) throws -> BackupQueue.Addition {
        try add(jobID: jobID, trigger: .scheduled, by: nil)
    }

    /// Takes a waiting run out of the queue, or stops a running one, which leaves its partial snapshot
    /// for the next run. Recorded in the audit log. False when the job has no run waiting or going.
    func cancel(jobID: UUID, by deviceID: UUID) throws -> Bool {
        switch try queue.cancel(jobID: jobID, by: deviceID, at: workflow.now()) {
        case .leftQueue:
            Self.logger.notice("Cancelled a waiting run")
            events.send(.leftQueue(jobID: jobID))
            return true
        case .running:
            Self.logger.notice("Cancelling the running run")
            if live?.entry.jobID == jobID { live?.task?.cancel() }
            return true
        case .notQueued:
            return false
        }
    }

    /// The run going now, as far as it has got, and what it's doing.
    func current() -> (entry: RunLogEntry, step: RunStep?)? {
        guard let live, let entry = live.entry.entry else { return nil }
        return (entry, live.step)
    }

    /// When Hive is stopping: stops the run going now and its processes, and starts nothing more. A run
    /// cut short is left unfinished, for the next start to mark interrupted and queue again.
    func stop() async {
        stopping = true
        if let live {
            Self.logger.notice("Stopping the run going now, as Hive stops")
            live.task?.cancel()
        }
        retentionPass?.cancel()
        await waitUntilIdle()
    }

    /// Returns once nothing is waiting or running.
    func waitUntilIdle() async {
        while let draining {
            await draining.value
        }
    }

    private func add(jobID: UUID, trigger: RunTrigger, by deviceID: UUID?) throws -> BackupQueue.Addition {
        let addition = try queue.add(jobID: jobID, trigger: trigger, at: workflow.now(), by: deviceID)
        if addition == .queued {
            Self.logger.notice("Queued a run: \(trigger.rawValue, privacy: .public)")
            events.send(.queued(jobID: jobID, trigger: trigger))
            kick()
        }
        return addition
    }

    private func kick() {
        guard draining == nil else { return }
        draining = Task { await drain() }
    }

    /// Runs whatever is waiting, one at a time, until nothing is. Anything queued meanwhile is picked up
    /// before it stops, since the actor runs nothing else between the last check and stopping.
    private func drain() async {
        while !stopping {
            if let next = nextInQueue() {
                // A store that can't start a run would otherwise give back the same run forever. What's
                // waiting goes once something is queued again, or Hive restarts.
                guard await run(next) else { break }
            } else if retentionWaiting {
                retentionWaiting = false
                await runRetention { await $0.pass() }
            } else {
                break
            }
        }
        draining = nil
    }

    private func runRetention(_ pass: @escaping @Sendable (RetentionWorkflow) async -> Void) async {
        let task = Task { [retention] in await pass(retention) }
        retentionPass = task
        await task.value
        retentionPass = nil
    }

    private func nextInQueue() -> QueuedRunRecord? {
        do {
            return try queue.next()
        } catch {
            Self.logger.error("Couldn't read the queue: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    /// False when the queue should stop: the run couldn't be started, or Hive is stopping.
    private func run(_ queued: QueuedRunRecord) async -> Bool {
        let started: JobLogRecord
        do {
            guard let entry = try queue.begin(queued, at: workflow.now()) else { return true }
            started = entry
        } catch {
            Self.logger.error("Couldn't start a run: \(String(describing: type(of: error)), privacy: .public)")
            return false
        }
        Self.logger.notice("Started a run: \(queued.trigger.rawValue, privacy: .public)")
        if let entry = started.entry { events.send(.started(entry)) }

        let task = Task { [workflow, driveWait] () -> BackupRun? in
            do {
                try await driveWait.untilMounted { self.report(.step(.waitingForDrive)) }
                return try await workflow.run(jobID: queued.jobID) { await self.report($0) }
            } catch {
                return nil
            }
        }
        live = Live(entry: started, step: nil, task: task)
        let allowSleep = sleep.preventSleep()
        let run = await task.value
        allowSleep()

        var finished = live?.entry ?? started
        live = nil
        // Left unfinished, and still marked running, for the next start to mark interrupted.
        if stopping, run == nil || run?.failure != nil { return false }
        finished.record(run ?? BackupRun(
            jobID: finished.jobID,
            startedAt: finished.startedAt,
            finishedAt: workflow.now(),
            failure: task.isCancelled ? .cancelled : .failed,
            directories: finished.directories,
            databases: finished.databases,
            pickedUpPartialSnapshot: finished.pickedUpPartialSnapshot
        ))
        do {
            try queue.finish(finished)
        } catch {
            Self.logger.error("Couldn't record the finished run: \(String(describing: type(of: error)), privacy: .public)")
        }
        if let entry = finished.entry { events.send(.finished(entry)) }
        if !stopping { await runRetention { await $0.pass(afterRunOf: queued.jobID) } }
        return true
    }

    private func report(_ report: BackupRunWorkflow.Report) {
        guard var current = live else { return }
        switch report {
        case .step(let step):
            current.step = step
            events.send(.step(jobID: current.entry.jobID, step: step))
        case .progress(let run):
            current.entry.record(run)
            // Saved as it goes, so a run cut short by a restart still shows what it did.
            try? queue.save(current.entry)
            if let entry = current.entry.entry { events.send(.progress(entry)) }
        }
        live = current
    }
}
