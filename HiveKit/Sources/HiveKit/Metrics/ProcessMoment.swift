/// A server's processes at a moment: the sample nearest it within the last day, or the hour's busiest
/// within the last 14 days (§6). Times are seconds since 1970 on the server's clock.
public enum ProcessMoment: Codable, Hashable, Sendable {
    case sample(takenAt: Int64, groups: [ProcessGroupFigures])
    /// The hour's top groups by average CPU and by average memory.
    case hour(startsAt: Int64, groups: [HourlyProcessGroupFigures])
    /// Nothing is kept for that moment.
    case notKept
}

/// Where a process group runs: a container, by its group's name as `CgroupMoment` gives it, or a
/// systemd service.
public struct ProcessGroupPlace: Codable, Hashable, Sendable {
    /// The container's full ID.
    public let containerID: String?
    /// The container's Swarm or Compose service, its name, or its short ID where Hive couldn't name it.
    public let containerGroup: String?
    /// The Compose project of a Compose service, since every project has its own `db`.
    public let composeProject: String?
    /// Such as `cron.service`.
    public let service: String?

    public init(containerID: String?, containerGroup: String?, composeProject: String? = nil, service: String?) {
        self.containerID = containerID
        self.containerGroup = containerGroup
        self.composeProject = composeProject
        self.service = service
    }
}

/// Processes sharing a command, a user and where they run, such as forty `php-fpm` workers in one
/// site's container.
public struct ProcessGroupFigures: Codable, Hashable, Sendable {
    public let command: String
    /// A name where the server has one, and a number for processes in a container, whose users are
    /// another system's.
    public let user: String
    /// Nil for processes in neither, such as a login shell, and in figures kept before Scout said
    /// where processes run.
    public let place: ProcessGroupPlace?
    public let count: Int
    /// Cores' worth, so 0.8 is 80% of one core. Missing from a Scout's first sample.
    public let cpuCores: Double?
    /// Approximate: what processes share is counted for none of them (§4).
    public let ownMemoryBytes: UInt64

    public init(command: String, user: String, place: ProcessGroupPlace? = nil, count: Int, cpuCores: Double?, ownMemoryBytes: UInt64) {
        self.command = command
        self.user = user
        self.place = place
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
    public let place: ProcessGroupPlace?
    public let highestCount: Int
    public let averageCPUCores: Double
    public let highestCPUCores: Double
    public let averageOwnMemoryBytes: UInt64
    public let highestOwnMemoryBytes: UInt64

    public init(
        command: String,
        user: String,
        place: ProcessGroupPlace? = nil,
        highestCount: Int,
        averageCPUCores: Double,
        highestCPUCores: Double,
        averageOwnMemoryBytes: UInt64,
        highestOwnMemoryBytes: UInt64
    ) {
        self.command = command
        self.user = user
        self.place = place
        self.highestCount = highestCount
        self.averageCPUCores = averageCPUCores
        self.highestCPUCores = highestCPUCores
        self.averageOwnMemoryBytes = averageOwnMemoryBytes
        self.highestOwnMemoryBytes = highestOwnMemoryBytes
    }
}
