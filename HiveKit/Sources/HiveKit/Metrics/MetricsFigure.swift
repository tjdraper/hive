/// What a server's figures are kept for: the server as a whole, or each filesystem, disk or interface
/// by name.
public enum MetricsSubjectKind: String, Codable, Hashable, Sendable {
    case server
    case filesystem
    case disk
    case networkInterface
}

/// One figure Hive keeps for a server, named as a series asks for it. Shares run from 0 to 1, rates are
/// per second, and memory and space are bytes.
public enum MetricsFigure: String, Codable, CaseIterable, Hashable, Sendable {
    case cores
    case cpuUser
    case cpuSystem
    case cpuIOWait
    case cpuSteal
    case loadOneMinute
    case loadFiveMinutes
    case loadFifteenMinutes
    case memoryTotal
    case memoryAvailable
    case memoryCache
    case swapTotal
    case swapUsed
    /// Pages a second.
    case swapInPages
    case swapOutPages
    case pressureCPUSome
    case pressureCPUFull
    case pressureMemorySome
    case pressureMemoryFull
    case pressureIOSome
    case pressureIOFull
    case processes
    case zombies
    /// Processes that can be counted but not read, as other users' are to Hive on its own Mac, and
    /// the cores' worth of CPU they and the kernel used together. Nil where every process can be read.
    case otherUsersProcesses
    case otherUsersCPU

    case filesystemSize = "filesystem.size"
    case filesystemUsed = "filesystem.used"
    case filesystemAvailable = "filesystem.available"
    case filesystemInodesUsed = "filesystem.inodesUsed"
    case filesystemInodesFree = "filesystem.inodesFree"

    case diskReadBytes = "disk.readBytes"
    case diskWrittenBytes = "disk.writtenBytes"
    case diskReads = "disk.reads"
    case diskWrites = "disk.writes"
    case diskBusy = "disk.busy"

    case networkReceivedBytes = "networkInterface.receivedBytes"
    case networkSentBytes = "networkInterface.sentBytes"
    case networkReceiveErrors = "networkInterface.receiveErrors"
    case networkSendErrors = "networkInterface.sendErrors"
    case networkReceiveDrops = "networkInterface.receiveDrops"
    case networkSendDrops = "networkInterface.sendDrops"

    public var subject: MetricsSubjectKind {
        guard let dot = rawValue.firstIndex(of: ".") else { return .server }
        return MetricsSubjectKind(rawValue: String(rawValue[..<dot])) ?? .server
    }

    /// The figure's name within its subject, such as `available` for `filesystem.available`.
    public var name: String {
        guard let dot = rawValue.firstIndex(of: ".") else { return rawValue }
        return String(rawValue[rawValue.index(after: dot)...])
    }
}
