/// Docker containers or systemd services, read from their cgroups (§4): how many are running, and the
/// top 10 by CPU and the top 10 by memory, each sent once, so sorting by either gives its top 10.
public struct CgroupFigures: Codable, Hashable, Sendable {
    public var count: Int
    public var top: [CgroupUse]

    public init(count: Int, top: [CgroupUse]) {
        self.count = count
        self.top = top
    }
}

/// One container or service. A figure the server doesn't account for, such as I/O where the kernel's
/// `io` controller isn't turned on for it, is missing, and so are rates in the first sample it's in.
public struct CgroupUse: Codable, Hashable, Sendable {
    /// A container's full ID, 64 hexadecimal digits, or a service's unit name, such as `cron.service`.
    public var name: String
    /// Cores' worth of CPU used since the previous sample, so 0.8 is 80% of one core. Unlike a process
    /// group's, it includes work done by processes that started and finished in between.
    public var cpuCores: Double?
    /// Memory in use, less file cache the kernel can reclaim, as `docker stats` counts it.
    public var memoryBytes: UInt64?
    public var readBytesPerSecond: Double?
    public var writtenBytesPerSecond: Double?
    /// Processes in it, apart from any in cgroups of its own below it.
    public var processes: Int
    /// A container's command names, the one using the most memory first, so a container Hive can't
    /// name still says what it runs. Empty for a service, and where processes are hidden.
    public var commands: [String]

    public init(
        name: String,
        cpuCores: Double?,
        memoryBytes: UInt64?,
        readBytesPerSecond: Double?,
        writtenBytesPerSecond: Double?,
        processes: Int,
        commands: [String]
    ) {
        self.name = name
        self.cpuCores = cpuCores
        self.memoryBytes = memoryBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.writtenBytesPerSecond = writtenBytesPerSecond
        self.processes = processes
        self.commands = commands
    }
}
