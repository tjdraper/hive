import Foundation

/// A job removed from the configuration, or on a server that was, whose snapshots stayed on the chosen
/// backup drive. Its snapshots are read and deleted through the job's own endpoints.
public struct RemovedJob: Codable, Hashable, Identifiable, Sendable {
    public let jobID: UUID
    public let serverID: UUID
    /// As last known: from the configuration while the server is still there, and otherwise the job log
    /// or, failing that, the folders on the drive.
    public let serverName: String
    public let jobName: String
    public let isServerRemoved: Bool
    public let snapshotCount: Int
    /// Each file once. Nil until counted.
    public let usedBytes: Int64?
    public let newestSnapshotAt: Date

    public var id: UUID {
        jobID
    }

    public init(
        jobID: UUID,
        serverID: UUID,
        serverName: String,
        jobName: String,
        isServerRemoved: Bool,
        snapshotCount: Int,
        usedBytes: Int64?,
        newestSnapshotAt: Date
    ) {
        self.jobID = jobID
        self.serverID = serverID
        self.serverName = serverName
        self.jobName = jobName
        self.isServerRemoved = isServerRemoved
        self.snapshotCount = snapshotCount
        self.usedBytes = usedBytes
        self.newestSnapshotAt = newestSnapshotAt
    }
}
