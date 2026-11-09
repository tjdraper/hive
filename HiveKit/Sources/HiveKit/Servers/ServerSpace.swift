/// What a server's backup jobs take on the chosen backup drive, which its quota is measured against.
public struct ServerSpace: Codable, Hashable, Sendable {
    /// Each file counted once, however many snapshots link to it. Nil while a job's snapshots on the
    /// drive haven't been counted yet, which happens after its next run or retention pass.
    public let usedBytes: Int64?

    public init(usedBytes: Int64?) {
        self.usedBytes = usedBytes
    }
}
