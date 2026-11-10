import Foundation

/// Where a job stands: whether it's waiting or running, its last and next runs, and whether it's overdue.
public struct JobStatus: Codable, Hashable, Sendable {
    public let jobID: UUID
    public let state: JobRunState
    /// The run going now, as far as it has got.
    public let current: RunLogEntry?
    /// What the run going now is doing.
    public let step: RunStep?
    /// The newest finished run.
    public let lastRun: RunLogEntry?
    /// When its newest complete snapshot was made.
    public let lastSnapshotAt: Date?
    public let nextRunAt: Date?
    /// Set once the job has gone without a complete snapshot for longer than its times allow: when that
    /// happened.
    public let overdueSince: Date?

    public init(
        jobID: UUID,
        state: JobRunState,
        current: RunLogEntry?,
        step: RunStep?,
        lastRun: RunLogEntry?,
        lastSnapshotAt: Date?,
        nextRunAt: Date?,
        overdueSince: Date?
    ) {
        self.jobID = jobID
        self.state = state
        self.current = current
        self.step = step
        self.lastRun = lastRun
        self.lastSnapshotAt = lastSnapshotAt
        self.nextRunAt = nextRunAt
        self.overdueSince = overdueSince
    }
}

public enum JobRunState: String, Codable, Hashable, Sendable {
    case idle
    /// Queued behind other runs. Runs go one at a time.
    case waiting
    case running
}

public enum RunStep: Codable, Hashable, Sendable {
    /// Hive has just started, and gives the backup drive a few minutes to mount.
    case waitingForDrive
    case checkingDirectories
    case pulling(folder: String)
    case dumping(database: String)
    case completing
}

/// Sent as runs are queued, go and finish, for Beekeeper to show live.
public enum RunEvent: Codable, Hashable, Sendable {
    case queued(jobID: UUID, trigger: RunTrigger)
    /// Cancelled before it started. It leaves no entry in the job log.
    case leftQueue(jobID: UUID)
    case started(RunLogEntry)
    case step(jobID: UUID, step: RunStep)
    /// A directory or database finished.
    case progress(RunLogEntry)
    case finished(RunLogEntry)
    /// Retention removed snapshots from a job, or couldn't remove some, and logged it.
    case removed(RemovalLogEntry)
}
