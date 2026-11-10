import Foundation

/// Sent to ask what a server's quota would remove.
public struct QuotaEstimateRequest: Codable, Hashable, Sendable {
    public let quotaBytes: Int64?

    public init(quotaBytes: Int64?) {
        self.quotaBytes = quotaBytes
    }
}

/// How many snapshots a lower quota or lower tiers would remove at the next retention pass that the
/// saved ones don't. Removing one snapshot can leave its neighbors freeing more, so a quota may remove fewer.
public struct RemovalEstimate: Codable, Hashable, Sendable {
    /// At most this many. Nil when the snapshots' space hasn't been counted yet.
    public let snapshotCount: Int?

    public init(snapshotCount: Int?) {
        self.snapshotCount = snapshotCount
    }
}
