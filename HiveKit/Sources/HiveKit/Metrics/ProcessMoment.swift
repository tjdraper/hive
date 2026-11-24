/// A server's processes at a moment: the sample nearest it within the last day, or the hour's busiest
/// within the last 14 days (§6). Times are seconds since 1970 on the server's clock.
public enum ProcessMoment: Codable, Hashable, Sendable {
    case sample(takenAt: Int64, groups: [ProcessGroupFigures])
    /// The hour's top groups by average CPU and by average memory.
    case hour(startsAt: Int64, groups: [HourlyProcessGroupFigures])
    /// Nothing is kept for that moment.
    case notKept
}

/// Processes sharing a command and a user, such as forty `php-fpm` workers.
public struct ProcessGroupFigures: Codable, Hashable, Sendable {
    public let command: String
    public let user: String
    public let count: Int
    /// Cores' worth, so 0.8 is 80% of one core. Missing from a Scout's first sample.
    public let cpuCores: Double?
    /// Approximate: what processes share is counted for none of them (§4).
    public let ownMemoryBytes: UInt64

    public init(command: String, user: String, count: Int, cpuCores: Double?, ownMemoryBytes: UInt64) {
        self.command = command
        self.user = user
        self.count = count
        self.cpuCores = cpuCores
        self.ownMemoryBytes = ownMemoryBytes
    }
}

/// A group over an hour. A sample it wasn't among the top groups in counts as nothing, so its averages
/// are at least what's shown.
public struct HourlyProcessGroupFigures: Codable, Hashable, Sendable {
    public let command: String
    public let user: String
    public let highestCount: Int
    public let averageCPUCores: Double
    public let highestCPUCores: Double
    public let averageOwnMemoryBytes: UInt64
    public let highestOwnMemoryBytes: UInt64

    public init(
        command: String,
        user: String,
        highestCount: Int,
        averageCPUCores: Double,
        highestCPUCores: Double,
        averageOwnMemoryBytes: UInt64,
        highestOwnMemoryBytes: UInt64
    ) {
        self.command = command
        self.user = user
        self.highestCount = highestCount
        self.averageCPUCores = averageCPUCores
        self.highestCPUCores = highestCPUCores
        self.averageOwnMemoryBytes = averageOwnMemoryBytes
        self.highestOwnMemoryBytes = highestOwnMemoryBytes
    }
}
