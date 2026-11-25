/// A server's containers and services at a moment: the sample nearest it within the last day, or the
/// hour's busiest within the last 90 days (§6). Times are seconds since 1970 on the server's clock.
public enum CgroupMoment: Codable, Hashable, Sendable {
    /// `containerCount` and `serviceCount` count every one running; the lists hold the busiest.
    case sample(takenAt: Int64, containerCount: Int, serviceCount: Int, containers: [CgroupGroupFigures], services: [CgroupGroupFigures])
    /// The hour's busiest by average CPU and by average memory.
    case hour(startsAt: Int64, containers: [CgroupGroupFigures], services: [CgroupGroupFigures])
    case notKept
}

/// How Hive named a group of containers (§4). Every Compose project has its own `db`, so a Compose
/// service is named by its project too.
public enum ContainerGroupKind: String, Codable, Hashable, Sendable {
    /// Every replica of a Swarm service, such as `buzzingpixel_db`.
    case swarmService
    case composeService
    /// A container with neither, by its own name.
    case container
    /// A container Hive couldn't name, because it can't run `docker` on the server or the server has
    /// no SSH details. Its name is its short ID, and its commands say what it runs.
    case unnamed
}

/// A group of containers, or a systemd service. In a sample, its figures add up its containers'; over an
/// hour or a bucket, they're the averages and highest of those totals, a sample it wasn't among the
/// busiest in counting as nothing.
public struct CgroupGroupFigures: Codable, Hashable, Sendable {
    /// The Swarm or Compose service, the container's name or short ID, or the systemd unit, such as
    /// `cron.service`.
    public let name: String
    /// Nil for a systemd service.
    public let kind: ContainerGroupKind?
    public let composeProject: String?
    /// Containers in the group at once, the most at once over an hour. 1 for a service.
    public let containerCount: Int
    /// Cores' worth, so 0.8 is 80% of one core. A service's includes work by processes that started
    /// and finished between samples, such as cron jobs. Missing from a Scout's first sample.
    public let cpuCores: Double?
    /// Over an hour only.
    public let highestCPUCores: Double?
    /// In use, less file cache the kernel can reclaim. Missing where the server doesn't account for it.
    public let memoryBytes: UInt64?
    public let highestMemoryBytes: UInt64?
    /// In a sample only.
    public let readBytesPerSecond: Double?
    public let writtenBytesPerSecond: Double?
    public let processes: Int?
    /// The commands its containers run, the one using the most memory first.
    public let commands: [String]
    /// Each of its containers, in a sample only.
    public let containers: [ContainerFigures]

    public init(
        name: String,
        kind: ContainerGroupKind?,
        composeProject: String?,
        containerCount: Int,
        cpuCores: Double?,
        highestCPUCores: Double?,
        memoryBytes: UInt64?,
        highestMemoryBytes: UInt64?,
        readBytesPerSecond: Double?,
        writtenBytesPerSecond: Double?,
        processes: Int?,
        commands: [String],
        containers: [ContainerFigures]
    ) {
        self.name = name
        self.kind = kind
        self.composeProject = composeProject
        self.containerCount = containerCount
        self.cpuCores = cpuCores
        self.highestCPUCores = highestCPUCores
        self.memoryBytes = memoryBytes
        self.highestMemoryBytes = highestMemoryBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.writtenBytesPerSecond = writtenBytesPerSecond
        self.processes = processes
        self.commands = commands
        self.containers = containers
    }
}

/// One container in a sample.
public struct ContainerFigures: Codable, Hashable, Sendable {
    /// The full ID, 64 hexadecimal digits.
    public let id: String
    /// Its own name, such as `buzzingpixel_db.1.tatuwopj5rl0flt587xfuvh0u`, where Hive could name it.
    public let name: String?
    public let cpuCores: Double?
    public let memoryBytes: UInt64?
    public let processes: Int
    public let commands: [String]

    public init(id: String, name: String?, cpuCores: Double?, memoryBytes: UInt64?, processes: Int, commands: [String]) {
        self.id = id
        self.name = name
        self.cpuCores = cpuCores
        self.memoryBytes = memoryBytes
        self.processes = processes
        self.commands = commands
    }
}

/// A server's container groups and services over a range, in buckets as `MetricsSeries` sizes them.
/// Times are seconds since 1970 on the server's clock.
public struct CgroupSeries: Codable, Hashable, Sendable {
    public let bucketSeconds: Int64
    public let containers: [CgroupGroupSeries]
    public let services: [CgroupGroupSeries]

    public init(bucketSeconds: Int64, containers: [CgroupGroupSeries], services: [CgroupGroupSeries]) {
        self.bucketSeconds = bucketSeconds
        self.containers = containers
        self.services = services
    }
}

/// One group's or service's figures, a value for each bucket something was kept in, oldest first. A
/// bucket where it wasn't among the busiest has it as nothing, so a missing bucket is a gap in the
/// server's figures, not the group's.
public struct CgroupGroupSeries: Codable, Hashable, Sendable {
    public let name: String
    public let kind: ContainerGroupKind?
    public let composeProject: String?
    public let bucketStarts: [Int64]
    public let averageCPUCores: [Double]
    public let highestCPUCores: [Double]
    public let averageMemoryBytes: [Double]
    public let highestMemoryBytes: [Double]

    public init(
        name: String,
        kind: ContainerGroupKind?,
        composeProject: String?,
        bucketStarts: [Int64],
        averageCPUCores: [Double],
        highestCPUCores: [Double],
        averageMemoryBytes: [Double],
        highestMemoryBytes: [Double]
    ) {
        self.name = name
        self.kind = kind
        self.composeProject = composeProject
        self.bucketStarts = bucketStarts
        self.averageCPUCores = averageCPUCores
        self.highestCPUCores = highestCPUCores
        self.averageMemoryBytes = averageMemoryBytes
        self.highestMemoryBytes = highestMemoryBytes
    }
}
