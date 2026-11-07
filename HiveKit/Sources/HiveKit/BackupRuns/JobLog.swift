import Foundation

/// One run in the job log.
public struct JobLogEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: Int64
    public let serverID: UUID
    /// The names when it ran, so the entry reads the same after a rename or once the job is removed.
    public let serverName: String
    public let jobName: String
    public let trigger: RunTrigger
    public let run: BackupRun

    public init(id: Int64, serverID: UUID, serverName: String, jobName: String, trigger: RunTrigger, run: BackupRun) {
        self.id = id
        self.serverID = serverID
        self.serverName = serverName
        self.jobName = jobName
        self.trigger = trigger
        self.run = run
    }
}

/// Why a run was queued.
public enum RunTrigger: String, Codable, Hashable, Sendable {
    /// One of the job's times came, or passed while Hive was off or the Mac asleep.
    case scheduled
    case runNow
    /// Hive stopped or restarted during the job's last run. A run queued this way isn't queued again
    /// if it's interrupted too, so a run that brings Hive down can't do it on every start.
    case afterInterruption
}

public struct JobLogPage: Codable, Hashable, Sendable {
    public let entries: [JobLogEntry]
    /// Pass as `before` for the next, older page. Nil on the last page.
    public let nextBefore: Int64?

    public init(entries: [JobLogEntry], nextBefore: Int64?) {
        self.entries = entries
        self.nextBefore = nextBefore
    }
}
