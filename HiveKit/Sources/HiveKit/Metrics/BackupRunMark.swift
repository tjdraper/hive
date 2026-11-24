import Foundation

/// A backup run, for marking on a server's charts. Times are seconds since 1970 on the server's clock,
/// as Hive last knew its offset, so they line up with its figures.
public struct BackupRunMark: Codable, Hashable, Sendable {
    public let jobID: UUID
    /// As it was named when it ran.
    public let jobName: String
    public let startedAt: Int64
    /// Nil while it runs.
    public let finishedAt: Int64?
    public let failure: BackupFailure?

    public init(jobID: UUID, jobName: String, startedAt: Int64, finishedAt: Int64?, failure: BackupFailure?) {
        self.jobID = jobID
        self.jobName = jobName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.failure = failure
    }
}
