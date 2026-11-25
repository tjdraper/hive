public struct ProcessFigures: Codable, Hashable, Sendable {
    /// Every process, kernel threads and zombies included.
    public var count: Int
    /// Processes that have exited but whose parent hasn't collected them.
    public var zombies: Int
    /// Processes grouped by command and user: the top 10 groups by CPU and the top 10 by memory,
    /// each sent once, so sorting by either gives its top 10.
    public var groups: [ProcessGroup]
    /// Where some users' processes can be counted but not read, as other users' are on a Mac to a
    /// process that isn't root, what they use together. They're in no group. Nil where every process
    /// can be read.
    public var otherUsers: OtherUsersProcesses?

    public init(count: Int, zombies: Int, groups: [ProcessGroup], otherUsers: OtherUsersProcesses? = nil) {
        self.count = count
        self.zombies = zombies
        self.groups = groups
        self.otherUsers = otherUsers
    }
}

/// Processes that can be counted but not read. Their memory can't be worked out: on a Mac, what the
/// readable processes use adds up to more than the system counts as in use, since each counts memory
/// the system counts elsewhere, such as the graphics card's.
public struct OtherUsersProcesses: Codable, Hashable, Sendable {
    public var count: Int
    /// Cores' worth of CPU used since the previous sample: what every core together was busy, less
    /// what the readable processes used. So it also counts the kernel's own work. Missing from the
    /// first sample.
    public var cpuCores: Double?

    public init(count: Int, cpuCores: Double?) {
        self.count = count
        self.cpuCores = cpuCores
    }
}

/// Every process with one command name and user, in one container or service, so forty `php-fpm`
/// workers in one site's container show as one line.
public struct ProcessGroup: Codable, Hashable, Sendable {
    /// The kernel's name for the command, at most 15 characters.
    public var command: String
    /// The user's name, or their number where the server has no name for it. A container's users are
    /// always numbers, since the server's names for them are another system's.
    public var user: String
    /// The Docker container the processes run in, by its full ID.
    public var containerID: String?
    /// The systemd service the processes run in, such as `cron.service`. Nil for one in a container.
    public var service: String?
    public var count: Int
    /// Cores' worth of CPU used since the previous sample, so 0.8 is 80% of one core. Missing from
    /// the first sample.
    public var cpuCores: Double?
    /// Each process's resident memory less what it shares, such as libraries and a cache shared
    /// between workers, added up. Approximate: what processes share is counted for none of them.
    public var ownMemoryBytes: UInt64

    public init(
        command: String,
        user: String,
        containerID: String? = nil,
        service: String? = nil,
        count: Int,
        cpuCores: Double?,
        ownMemoryBytes: UInt64
    ) {
        self.command = command
        self.user = user
        self.containerID = containerID
        self.service = service
        self.count = count
        self.cpuCores = cpuCores
        self.ownMemoryBytes = ownMemoryBytes
    }
}
