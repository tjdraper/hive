/// A physical or virtual machine's disk, such as `sda` or `nvme0n1`. Partitions and the devices
/// layered on disks, such as LVM and RAID, aren't sent, so no activity is counted twice.
public struct DiskFigures: Codable, Hashable, Sendable {
    public var name: String
    /// Missing from the first sample.
    public var activity: DiskActivity?

    public init(name: String, activity: DiskActivity?) {
        self.name = name
        self.activity = activity
    }
}

/// Since the previous sample.
public struct DiskActivity: Codable, Hashable, Sendable {
    public var readBytesPerSecond: Double
    public var writtenBytesPerSecond: Double
    public var readsPerSecond: Double
    public var writesPerSecond: Double
    /// The share of time, from 0 to 1, the disk had requests in progress. Missing on a Mac, which
    /// counts only how long requests took, and those overlap.
    public var busy: Double?

    public init(readBytesPerSecond: Double, writtenBytesPerSecond: Double, readsPerSecond: Double, writesPerSecond: Double, busy: Double?) {
        self.readBytesPerSecond = readBytesPerSecond
        self.writtenBytesPerSecond = writtenBytesPerSecond
        self.readsPerSecond = readsPerSecond
        self.writesPerSecond = writesPerSecond
        self.busy = busy
    }
}
