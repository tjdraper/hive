/// One minute of a server's figures from samples Scout held while Hive was unreachable for more than
/// an hour. Each figure is the average and the highest of the minute's samples, and the lowest only
/// where it matters, such as available memory and space.
public struct MetricsMinute: Codable, Hashable, Sendable {
    /// Seconds since 1970 on the server's clock, on a minute mark.
    public var startsAt: Int64
    public var sampleCount: Int
    public var average: MinuteFigures
    public var highest: MinuteFigures
    public var lowest: MinuteLows

    public init(startsAt: Int64, sampleCount: Int, average: MinuteFigures, highest: MinuteFigures, lowest: MinuteLows) {
        self.startsAt = startsAt
        self.sampleCount = sampleCount
        self.average = average
        self.highest = highest
        self.lowest = lowest
    }
}

/// A sample's figures without the server's facts and processes, which a minute doesn't keep. A figure
/// missing from some of the minute's samples, such as a rate in the first, is worked out from the
/// others; a filesystem, disk or interface from the samples it was in.
public struct MinuteFigures: Codable, Hashable, Sendable {
    public var cpu: CPUFigures?
    public var memory: MemoryFigures?
    public var pressure: PressureFigures?
    public var filesystems: [FilesystemFigures]
    public var disks: [DiskFigures]
    public var networkInterfaces: [NetworkInterfaceFigures]

    public init(
        cpu: CPUFigures?,
        memory: MemoryFigures?,
        pressure: PressureFigures?,
        filesystems: [FilesystemFigures],
        disks: [DiskFigures],
        networkInterfaces: [NetworkInterfaceFigures]
    ) {
        self.cpu = cpu
        self.memory = memory
        self.pressure = pressure
        self.filesystems = filesystems
        self.disks = disks
        self.networkInterfaces = networkInterfaces
    }
}

/// The lowest of a minute's figures where a dip matters: running short of memory or space shows in
/// the lowest, and an average would hide it.
public struct MinuteLows: Codable, Hashable, Sendable {
    public var memoryAvailableBytes: UInt64?
    public var filesystems: [FilesystemLows]

    public init(memoryAvailableBytes: UInt64?, filesystems: [FilesystemLows]) {
        self.memoryAvailableBytes = memoryAvailableBytes
        self.filesystems = filesystems
    }
}

public struct FilesystemLows: Codable, Hashable, Sendable {
    public var mountPoint: String
    public var availableBytes: UInt64
    public var inodesFree: UInt64?

    public init(mountPoint: String, availableBytes: UInt64, inodesFree: UInt64?) {
        self.mountPoint = mountPoint
        self.availableBytes = availableBytes
        self.inodesFree = inodesFree
    }
}
