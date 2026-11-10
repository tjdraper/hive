import Foundation

/// The snapshots retention removed from one job in one pass, and any it meant to remove but couldn't.
public struct RemovalLogEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: Int64
    public let jobID: UUID
    public let serverID: UUID
    /// The names at the time, so the entry reads the same after a rename or once the job is removed.
    public let serverName: String
    public let jobName: String
    public let date: Date
    public let removed: [RemovedSnapshot]
    public let notRemoved: [UnremovedSnapshot]

    public init(
        id: Int64,
        jobID: UUID,
        serverID: UUID,
        serverName: String,
        jobName: String,
        date: Date,
        removed: [RemovedSnapshot],
        notRemoved: [UnremovedSnapshot]
    ) {
        self.id = id
        self.jobID = jobID
        self.serverID = serverID
        self.serverName = serverName
        self.jobName = jobName
        self.date = date
        self.removed = removed
        self.notRemoved = notRemoved
    }
}

public struct RemovedSnapshot: Codable, Hashable, Sendable {
    public let snapshotID: UUID
    /// When it completed, or for a partial snapshot, when it started.
    public let date: Date
    public let wasComplete: Bool
    public let reason: RemovalReason
    /// What removing it freed on the backup drive. Files it shared with other snapshots stay.
    public let bytesFreed: Int64

    public init(snapshotID: UUID, date: Date, wasComplete: Bool, reason: RemovalReason, bytesFreed: Int64) {
        self.snapshotID = snapshotID
        self.date = date
        self.wasComplete = wasComplete
        self.reason = reason
        self.bytesFreed = bytesFreed
    }
}

public struct UnremovedSnapshot: Codable, Hashable, Sendable {
    public let snapshotID: UUID
    /// When it completed, or for a partial snapshot, when it started.
    public let date: Date
    public let wasComplete: Bool
    public let reason: RemovalReason
    public let problem: RemovalProblem

    public init(snapshotID: UUID, date: Date, wasComplete: Bool, reason: RemovalReason, problem: RemovalProblem) {
        self.snapshotID = snapshotID
        self.date = date
        self.wasComplete = wasComplete
        self.reason = reason
        self.problem = problem
    }
}

public enum RemovalReason: String, Codable, Hashable, Sendable {
    /// Neither of the job's tiers keeps it.
    case outsideTiers
    /// A partial snapshot a failed run left, once a newer snapshot completed.
    case replacedPartial
    /// The server was over its quota, and this was its oldest daily snapshot.
    case quota
    /// A device deleted it, with its confirmation key.
    case deletedByDevice
}

public enum RemovalProblem: String, Codable, Hashable, Sendable {
    /// Its folder isn't a real folder inside its job's folder on the backup drive, where the catalog
    /// says it is. Hive removes nothing anywhere else.
    case notInJobFolder
    /// A run was writing to its job's snapshots.
    case beingWritten
    /// Hive couldn't remove all of it. What's left is removed on a later pass.
    case couldNotRemove
}
