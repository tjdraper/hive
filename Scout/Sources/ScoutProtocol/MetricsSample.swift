/// One reading of a server's figures, taken on a 10-second mark of the server's clock.
public struct MetricsSample: Codable, Hashable, Sendable {
    /// Seconds since 1970 on the server's clock, which may differ from Hive's.
    public var takenAt: Int64
    public var server: ServerFacts

    public init(takenAt: Int64, server: ServerFacts) {
        self.takenAt = takenAt
        self.server = server
    }
}
